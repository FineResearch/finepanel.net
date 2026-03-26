# frozen_string_literal: true

require 'uri'
require 'cgi'

class TrackedSurveysController < ApplicationController
  skip_before_action :verify_authenticity_token

  TRACKING_HOST = 'survey-wp.finepanel.net'.freeze
  ORIGINAL_HOST = 'survey.confirmit.com'.freeze

  def health
    render plain: 'ok', status: :ok
  end

  def redirect
    tracked_path = normalized_tracked_path
    query_hash = request.query_parameters.to_h
    survey_r = query_hash['r'].presence
    survey_s = query_hash['s'].presence

    is_cancel = cancel_request?(query_hash)

    panelist_record =
      if is_cancel
        WhatsappProjectPanelist.find_for_cancel_click(
          path: tracked_path,
          r: survey_r,
          s: survey_s
        )
      else
        WhatsappProjectPanelist.find_for_survey_click(
          path: tracked_path,
          r: survey_r,
          s: survey_s
        )
      end

    if panelist_record.present?
      safely_update_tracking(panelist_record, is_cancel: is_cancel)
      target_url = build_redirect_url_from_record(
        panelist_record: panelist_record,
        is_cancel: is_cancel
      )
    else
      Rails.logger.warn(
        "[TrackedSurveysController] No WhatsappProjectPanelist found " \
        "path=#{tracked_path} r=#{survey_r} s=#{survey_s} cancel=#{is_cancel}"
      )

      target_url = build_fallback_redirect_url(
        tracked_path: tracked_path,
        original_query_hash: query_hash,
        is_cancel: is_cancel
      )
    end

    Rails.logger.info(
      "[TrackedSurveysController] Redirecting " \
      "path=#{tracked_path} r=#{survey_r} s=#{survey_s} cancel=#{is_cancel} " \
      "panelist_record_id=#{panelist_record&.id} target_url=#{target_url}"
    )

    redirect_to target_url
  rescue StandardError => e
    Rails.logger.error("[TrackedSurveysController] Error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
    head :internal_server_error
  end

  private

  def normalized_tracked_path
    path = request.path.to_s
    path = "/#{path}" unless path.start_with?('/')
    path
  end

  def cancel_request?(query_hash)
    query_hash['exit'].to_s.downcase == 'cancelar'
  end

  def safely_update_tracking(panelist_record, is_cancel:)
    if is_cancel
      return if panelist_record.status == 'cancelled'

      panelist_record.mark_cancelled!
    else
      return if final_or_cancelled_status?(panelist_record.status)

      panelist_record.mark_started! unless panelist_record.status == 'survey_started'
    end
  rescue StandardError => e
    Rails.logger.error(
      "[TrackedSurveysController] Tracking update failed record_id=#{panelist_record.id} " \
      "cancel=#{is_cancel} error=#{e.class} - #{e.message}"
    )
  end

  def final_or_cancelled_status?(status)
    %w[
      cancelled
      filtered_with_agent
      filtered_without_agent
      completed_with_agent
      completed_without_agent
    ].include?(status.to_s)
  end

  def build_redirect_url_from_record(panelist_record:, is_cancel:)
    original_link =
      if is_cancel
        panelist_record.original_cancel_link.presence || panelist_record.original_survey_link
      else
        panelist_record.original_survey_link
      end

    if is_cancel
      WhatsApp::TrackedLinkBuilder.final_cancel_redirect_link(
        original_link,
        panelist_record.whatsapp_number
      )
    else
      WhatsApp::TrackedLinkBuilder.final_survey_redirect_link(
        original_link,
        panelist_record.whatsapp_number
      )
    end
  end

  def build_fallback_redirect_url(tracked_path:, original_query_hash:, is_cancel:)
    uri = URI::HTTPS.build(host: ORIGINAL_HOST, path: tracked_path)

    query_hash = original_query_hash.deep_dup
    query_hash['exit'] = 'cancelar' if is_cancel

    uri.query = URI.encode_www_form(query_hash.to_a)
    uri.to_s
  end
end
