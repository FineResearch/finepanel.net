module Api
  module V1
    class WebhooksController < ApiController
      COUNTRY_BY_PREFIX = {
        '598'  => 'Uruguay',
        '595'  => 'Paraguay',
        '593'  => 'Ecuador',
        '591'  => 'Bolivia',
        '507'  => 'Panamá',
        '506'  => 'Costa Rica',
        '505'  => 'Nicaragua',
        '504'  => 'Honduras',
        '503'  => 'El Salvador',
        '502'  => 'Guatemala',
        '351'  => 'Portugal',
        '1939' => 'Puerto Rico',
        '1787' => 'Puerto Rico',
        '1849' => 'República Dominicana',
        '1829' => 'República Dominicana',
        '1809' => 'República Dominicana',
        '58'   => 'Venezuela',
        '57'   => 'Colombia',
        '56'   => 'Chile',
        '55'   => 'Brasil',
        '54'   => 'Argentina',
        '52'   => 'México',
        '51'   => 'Perú',
        '34'   => 'España'
      }.freeze

      OPT_IN_TEMPLATE_NAMES = %w[preferencia_es preferencia_pt].freeze
      OPT_IN_RESPONSE_WINDOW = 7.days

      def handle_whatsapp_response
        if request.get?
          handle_webhook_config
        else
          handle_inbound_message
        end
      end

      private


def register_invalid_whatsapp!(panelist_id:, panelist_email:, whatsapp_number:, project_code:, error_message:)
  return if whatsapp_number.blank?

  normalized_number = normalize_phone(whatsapp_number)

  record = InvalidWhatsappNumber.find_by(whatsapp_number: normalized_number)

  if record
    record.update!(
      panelist_id: record.panelist_id.presence || panelist_id,
      panelist_email: panelist_email,
      last_detected_project_code: project_code,
      last_detected_at: Time.current,
      times_detected: record.times_detected.to_i + 1,
      last_error_message: error_message,
      active: true
    )
  else
    InvalidWhatsappNumber.create!(
      panelist_id: panelist_id,
      panelist_email: panelist_email,
      whatsapp_number: normalized_number,
      first_detected_project_code: project_code,
      last_detected_project_code: project_code,
      first_detected_at: Time.current,
      last_detected_at: Time.current,
      times_detected: 1,
      last_error_message: error_message,
      active: true
    )
  end
end

def process_whatsapp_statuses!(statuses, payload)
  Array(statuses).each do |status_payload|
    Rails.logger.info(
      "[WhatsAppStatus] payload=#{status_payload.inspect}"
    )

    status_value = status_payload['status'].to_s
    recipient_id = normalize_phone(status_payload['recipient_id'])
    message_id = status_payload['id'].to_s
    timestamp = parse_timestamp(status_payload['timestamp'])

    error = Array(status_payload['errors']).first
    error_code = error&.dig('code').to_s
    error_title = error&.dig('title').to_s
    error_message = error&.dig('message').to_s
    error_details = error&.dig('error_data', 'details').to_s

    outbound = WhatsappOutbound.where(whatsapp_number: recipient_id)
                               .order(created_at: :desc)
                               .first

    WhatsappDeliveryResult.create!(
      project_code: outbound&.project_code,
      sample_number: outbound&.sample_number,
      panelist_id: outbound&.panelist_id,
      panelist_email: outbound&.panelist_email,
      whatsapp_number: recipient_id,
      status: status_value,
      error_message: [
        error_code,
        error_title,
        error_message,
        error_details
      ].reject(&:blank?).join(' - ')
    )

    if status_value == 'failed' && error_code == '131026'
      register_invalid_whatsapp!(
        panelist_id: outbound&.panelist_id,
        panelist_email: outbound&.panelist_email,
        whatsapp_number: recipient_id,
        project_code: outbound&.project_code,
        error_message: [
          error_code,
          error_title,
          error_message,
          error_details
        ].reject(&:blank?).join(' - ')
      )
    end
  end
rescue StandardError => e
  Rails.logger.error("[WhatsAppStatus] Error: #{e.class} - #{e.message}")
  Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
end



      def handle_webhook_config
        mode = params['hub.mode']
        token = params['hub.verify_token']
        challenge = params['hub.challenge']

        if mode.present? && token.present?
          if mode == 'subscribe' && token == 'FINEPANEL'
            Rails.logger.info('[WhatsAppInbound] WEBHOOK_VERIFIED')
            render plain: challenge, status: :ok
          else
            head :forbidden
          end
        else
          head :bad_request
        end
      end

      def handle_inbound_message
        payload = params.to_unsafe_h
        Rails.logger.info("[WhatsAppInboundRaw] payload=#{payload.to_json}")

        value = payload.dig('entry', 0, 'changes', 0, 'value')
        contact_information = value&.dig('contacts', 0)
        message_information = value&.dig('messages', 0)

statuses = value&.dig('statuses')

if statuses.present?
  process_whatsapp_statuses!(statuses, payload)
  return head :ok
end


        unless message_information.present?
          Rails.logger.info("[WhatsAppInbound] No inbound message found. Payload: #{payload}")
          return head :ok
        end

        wa_number = normalize_phone(contact_information&.dig('wa_id') || message_information&.dig('from'))
        profile_name = contact_information&.dig('profile', 'name')
        message_type = message_information&.dig('type')
        from_number = normalize_phone(message_information&.dig('from'))
        timestamp = parse_timestamp(message_information&.dig('timestamp'))
        message_id = message_information&.dig('id')
        phone_number_id = value&.dig('metadata', 'phone_number_id')
        display_phone_number = value&.dig('metadata', 'display_phone_number')

        message_body =
          message_information&.dig('text', 'body') ||
          message_information&.dig('button', 'text') ||
          message_information&.dig('interactive', 'button_reply', 'title') ||
          message_information&.dig('interactive', 'list_reply', 'title')

        message_body = message_body.to_s.strip
        message_body = "[#{message_type}]" if message_body.blank?

        inbound_number = wa_number.presence || from_number
        panelist_country = country_from_phone(inbound_number)

        user = find_user_by_whatsapp(inbound_number)
        last_outbound = find_last_outbound(user, inbound_number)
        panelist_record = find_project_panelist(
          last_outbound: last_outbound,
          inbound_number: inbound_number
        )

        conversation = find_or_create_conversation(
          user: user,
          last_outbound: last_outbound,
          inbound_number: inbound_number,
          panelist_country: panelist_country
        )

        if conversation.present?
          WhatsappMessage.create!(
            whatsapp_conversation: conversation,
            direction: 'inbound',
            source: 'webhook',
            message_type: message_type,
            message_body: message_body,
            message_id: message_id,
            status: 'received',
            from_phone_number: inbound_number,
            from_phone_number_id: phone_number_id,
            to_phone_number: display_phone_number,
            payload_json: payload.to_json,
            received_at: timestamp
          )

          conversation.touch_inbound!
        end

        panelist_record&.mark_reply_received!

        Rails.logger.info(
          "[WhatsAppInbound] message_id=#{message_id} from=#{from_number} wa_number=#{wa_number} " \
          "profile_name=#{profile_name} type=#{message_type} body=#{message_body} " \
          "timestamp=#{timestamp} phone_number_id=#{phone_number_id} display_phone_number=#{display_phone_number} " \
          "panelist_country=#{panelist_country} user_id=#{user&.id} " \
          "conversation_id=#{conversation&.id} panelist_record_id=#{panelist_record&.id} " \
          "last_project_code=#{last_outbound&.project_code} last_sample_number=#{last_outbound&.sample_number} " \
          "last_subject=#{last_outbound&.subject} last_template_name=#{last_outbound&.template_name} " \
          "support_email=#{last_outbound&.support_email}"
        )

        if cancellation_request?(message_body)
          process_text_opt_out!(
            inbound_number: inbound_number,
            profile_name: profile_name,
            phone_number_id: phone_number_id,
            panelist_record: panelist_record,
            last_outbound: last_outbound,
            conversation: conversation
          )

          return head :ok
        end

        if opt_in_request?(message_body, last_outbound)
          process_opt_in_request!(
            inbound_number: inbound_number,
            phone_number_id: phone_number_id,
            user: user,
            panelist_record: panelist_record,
            last_outbound: last_outbound,
            conversation: conversation
          )

          return head :ok
        end

        if opt_in_courtesy_after_confirmation?(message_body, message_type, last_outbound, conversation)
          Rails.logger.info(
            "[WhatsAppInbound] opt_in_courtesy_auto_resolved conversation_id=#{conversation&.id} " \
            "body=#{message_body.inspect} type=#{message_type}"
          )

          conversation.mark_resolved!(nil) if conversation.present?

          return head :ok
        end

        if request_link_now?(message_body)
          process_request_link_now!(
            inbound_number: inbound_number,
            phone_number_id: phone_number_id,
            panelist_record: panelist_record,
            last_outbound: last_outbound
          )

          return head :ok
        end

        if postpone_request?(message_body)
          process_postpone_request!(
            inbound_number: inbound_number,
            phone_number_id: phone_number_id,
            panelist_record: panelist_record,
            last_outbound: last_outbound
          )

          return head :ok
        end

        panelist_user = panelist_record&.user || user
        panelist_first_name = panelist_user&.first_name
        panelist_last_name = panelist_user&.last_name
        panelist_email = last_outbound&.panelist_email

support_email = last_outbound&.support_email.to_s.strip.presence

unless support_email.present?
  Rails.logger.info(
    "[WhatsAppInbound] inbound_alert_skipped_no_support_email conversation_id=#{conversation&.id} " \
    "project_code=#{last_outbound&.project_code} panelist_id=#{last_outbound&.panelist_id}"
  )

  return head :ok
end

        WhatsappMailer.inbound_message_alert(
          profile_name: profile_name,
          from_number: inbound_number,
          user_id: user&.id,
          message_body: message_body,
          message_id: message_id,
          message_type: message_type,
          timestamp: timestamp.respond_to?(:iso8601) ? timestamp.iso8601 : timestamp.to_s,
          phone_number_id: phone_number_id,
          display_phone_number: display_phone_number,
          panelist_country: panelist_country,
          project_code: last_outbound&.project_code,
          sample_number: last_outbound&.sample_number,
          support_email: support_email,
          survey_subject: last_outbound&.subject,
          duration: last_outbound&.duration,
          incentive: last_outbound&.incentive,
          sent_by: last_outbound&.sent_by,
          survey_link: last_outbound&.survey_link,
          main_survey_link: last_outbound&.main_survey_link,
          panelist_id: last_outbound&.panelist_id,
          from_phone_number: last_outbound&.from_phone_number,
          from_phone_number_id: last_outbound&.from_phone_number_id,
          include_respondent_phone: last_outbound&.include_respondent_phone,
          respondent_phone: inbound_number,
          panelist_first_name: panelist_first_name,
          panelist_last_name: panelist_last_name,
          panelist_email: panelist_email
        ).deliver_later

        head :ok
      rescue StandardError => e
        Rails.logger.error("[WhatsAppInbound] Error: #{e.class} - #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
        head :ok
      end

      def find_project_panelist(last_outbound:, inbound_number:)
        record =
          if last_outbound.present?
            WhatsappProjectPanelist.find_by(
              project_code: last_outbound.project_code,
              panelist_id: last_outbound.panelist_id
            )
          end

        record ||= WhatsappProjectPanelist.find_by(
          whatsapp_number: normalize_phone(inbound_number)
        )

        record
      end

      def process_request_link_now!(inbound_number:, phone_number_id:, panelist_record:, last_outbound:)
        survey_link =
          panelist_record&.tracked_survey_link.presence ||
          panelist_record&.original_survey_link.presence ||
          last_outbound&.main_survey_link.presence ||
          last_outbound&.survey_link.presence

        if survey_link.blank?
          Rails.logger.warn(
            "[WhatsAppInbound] request_link_now but no survey_link found from=#{inbound_number} panelist_record_id=#{panelist_record&.id} last_outbound_id=#{last_outbound&.id}"
          )
          return
        end

        message = request_link_now_message(inbound_number, survey_link)

        Rails.logger.info(
          "[WhatsAppInbound] Sending survey link after reply=1 to=#{inbound_number} phone_number_id=#{phone_number_id}"
        )

        WhatsApp::Client.new.send_text_message(
          phone_number_id: phone_number_id,
          to_number: inbound_number,
          body: message
        )

        if panelist_record.present? && panelist_record.status.to_s == 'postponed'
          panelist_record.update!(status: 'sent_no_response')
        end
      rescue StandardError => e
        Rails.logger.error(
          "[WhatsAppInbound] request_link_now failed to=#{inbound_number} error=#{e.class} message=#{e.message}"
        )
      end

      def process_postpone_request!(inbound_number:, phone_number_id:, panelist_record:, last_outbound:)
        if panelist_record.present?
          panelist_record.mark_postponed!
        end

        message = postpone_confirmation_message(inbound_number)

        Rails.logger.info(
          "[WhatsAppInbound] Sending postpone confirmation to=#{inbound_number} phone_number_id=#{phone_number_id} " \
          "project_code=#{panelist_record&.project_code || last_outbound&.project_code} " \
          "panelist_id=#{panelist_record&.panelist_id || last_outbound&.panelist_id}"
        )

        WhatsApp::Client.new.send_text_message(
          phone_number_id: phone_number_id,
          to_number: inbound_number,
          body: message
        )
      rescue StandardError => e
        Rails.logger.error(
          "[WhatsAppInbound] postpone confirmation failed to=#{inbound_number} error=#{e.class} message=#{e.message}"
        )
      end

      def opt_in_request?(message_body, last_outbound)
        return false unless opt_in_context?(last_outbound)

        body_contains_ok?(message_body)
      end

      def opt_in_context?(last_outbound)
        return false if last_outbound.blank?
        return false unless OPT_IN_TEMPLATE_NAMES.include?(last_outbound.template_name.to_s)

        sent_at = last_outbound.created_at
        return false if sent_at.blank?

        sent_at >= OPT_IN_RESPONSE_WINDOW.ago
      end

      def body_contains_ok?(message_body)
        body = message_body.to_s.strip
        return false if body.blank?

        normalized = I18n.transliterate(body).downcase
        normalized.match?(/\bok\b/)
      rescue StandardError
        false
      end

      def opt_in_courtesy_after_confirmation?(message_body, message_type, last_outbound, conversation)
        return false if conversation.blank?
        return false unless opt_in_context?(last_outbound)

        normalized = normalize_courtesy_text(message_body)
        return false if normalized.blank? && message_type.to_s != 'reaction'

        return false if word_count(normalized) >= 6

        return true if message_type.to_s == 'reaction'

        courtesy_keywords = %w[
          gracias
          obrigado
          obrigada
          ok
          perfecto
          perfeito
          vale
          listo
          entendido
          👍
          🙏
          👌
        ]

        courtesy_keywords.any? { |keyword| normalized.include?(keyword) }
      end

      def normalize_courtesy_text(message_body)
        I18n.transliterate(message_body.to_s.strip.downcase)
      rescue StandardError
        message_body.to_s.strip.downcase
      end

      def word_count(text)
        text.to_s
            .gsub(/[^\p{L}\p{N}\s]/u, '')
            .scan(/\S+/)
            .size
      end

      def process_opt_in_request!(inbound_number:, phone_number_id:, user:, panelist_record:, last_outbound:, conversation:)
        target_user = panelist_record&.user || user

        if target_user.present?
          target_user.update!(
            whatsapp_opt_in: true,
            whatsapp_opt_in_at: Time.current,
            whatsapp_opt_in_source: 'whatsapp_template_preference'
          )
        end

        message = opt_in_confirmation_message(inbound_number)

        Rails.logger.info(
          "[WhatsAppInbound] opt_in confirmed to=#{inbound_number} user_id=#{target_user&.id} " \
          "project_code=#{panelist_record&.project_code || last_outbound&.project_code} " \
          "panelist_id=#{panelist_record&.panelist_id || last_outbound&.panelist_id} " \
          "template_name=#{last_outbound&.template_name}"
        )

        response = WhatsApp::Client.new.send_text_message(
          phone_number_id: phone_number_id,
          to_number: inbound_number,
          body: message
        )

        if conversation.present?
          conversation.whatsapp_messages.create!(
            direction: 'outbound',
            source: 'system',
            message_type: 'text',
            message_body: message,
            status: 'sent',
            from_phone_number: last_outbound&.from_phone_number,
            from_phone_number_id: phone_number_id,
            to_phone_number: inbound_number,
            payload_json: response.to_json
          )

          conversation.touch_outbound!
          conversation.mark_resolved!(nil)
        end
      rescue StandardError => e
        Rails.logger.error(
          "[WhatsAppInbound] opt_in confirmation failed to=#{inbound_number} error=#{e.class} message=#{e.message}"
        )
      end

      def opt_in_confirmation_message(phone)
        normalized = normalize_phone(phone)

        if normalized.start_with?('55')
          'Perfeito, muito obrigado! Vamos entrar em contato quando houver pesquisas relevantes para o seu perfil. '
        else
          'Perfecto, muchas gracias! Vamos a contactarle cuando haya estudios relevantes para su perfil.'
        end
      end

      def process_text_opt_out!(inbound_number:, profile_name:, phone_number_id:, panelist_record:, last_outbound:, conversation:)
        Rails.logger.info(
          "[WhatsAppInbound] Opt-out request detected from=#{inbound_number} profile_name=#{profile_name}"
        )

        if panelist_record.present? && panelist_record.status != 'cancelled'
          Rails.logger.info(
            "[WhatsAppInbound] Marking panelist as cancelled project_code=#{panelist_record.project_code} panelist_id=#{panelist_record.panelist_id}"
          )

          panelist_record.mark_cancelled!
        else
          Rails.logger.info(
            "[WhatsAppInbound] Panelist already cancelled or not found project_code=#{panelist_record&.project_code} panelist_id=#{panelist_record&.panelist_id}"
          )
        end

        exclusion_link =
          panelist_record&.tracked_cancel_link.presence ||
          panelist_record&.original_cancel_link.presence

        support_email = opt_out_support_email(inbound_number)

        Rails.logger.info(
          "[WhatsAppInbound] Queueing opt-out email to=#{support_email} exclusion_link=#{exclusion_link}"
        )

	panelist_user = panelist_record&.user || last_outbound&.user        

if panelist_user.present?
  panelist_user.update!(
    whatsapp_opt_in: false,
    whatsapp_opt_in_at: nil,
    whatsapp_opt_in_source: 'whatsapp_cancelar'
  )

  Rails.logger.info(
    "[WhatsAppInbound] User marked as whatsapp opt-out user_id=#{panelist_user.id} phone=#{inbound_number}"
  )
end


WhatsappMailer.whatsapp_opt_out_alert(
  support_email: support_email,
  exclusion_link: exclusion_link.to_s,
  from_number: inbound_number,
  profile_name: profile_name,
  project_code: panelist_record&.project_code || last_outbound&.project_code,
  panelist_id: panelist_record&.panelist_id || last_outbound&.panelist_id,
  panelist_first_name: panelist_user&.first_name,
  panelist_last_name: panelist_user&.last_name,
  panelist_email: last_outbound&.panelist_email,
  panelist_country: panelist_record&.country || panelist_user&.country
).deliver_later

        begin
          message = opt_out_confirmation_message(inbound_number)

          Rails.logger.info(
            "[WhatsAppInbound] Sending opt-out confirmation via WhatsApp to=#{inbound_number} phone_number_id=#{phone_number_id}"
          )

          response = WhatsApp::Client.new.send_text_message(
            phone_number_id: phone_number_id,
            to_number: inbound_number,
            body: message


          )

if conversation.present?
  conversation.whatsapp_messages.create!(
    direction: 'outbound',
    source: 'system',
    message_type: 'text',
    message_body: message,
    status: 'sent',
    from_phone_number: last_outbound&.from_phone_number,
    from_phone_number_id: phone_number_id,
    to_phone_number: inbound_number,
    payload_json: response.to_json
  )

  conversation.touch_outbound!
  conversation.mark_resolved!(nil)
end

          Rails.logger.info(
            "[WhatsAppInbound] Opt-out confirmation sent successfully to=#{inbound_number} response=#{response.inspect}"
          )
        rescue StandardError => e
          Rails.logger.error(
            "[WhatsAppInbound] Opt-out confirmation send failed to=#{inbound_number} error=#{e.class} message=#{e.message}"
          )
        end

        Rails.logger.info(
          "[WhatsAppInbound] opt_out_processed from=#{inbound_number} " \
          "project_code=#{panelist_record&.project_code || last_outbound&.project_code} " \
          "panelist_id=#{panelist_record&.panelist_id || last_outbound&.panelist_id} " \
          "support_email=#{support_email} exclusion_link=#{exclusion_link}"
        )
      end

      def cancellation_request?(message_body)
        normalized = normalize_inbound_text(message_body)

        opt_out_keywords = %w[
          cancelar
          baja
          baixa
          stop
        ]

        match = opt_out_keywords.include?(normalized)

        if match
          Rails.logger.info(
            "[WhatsAppInbound] cancellation keyword detected body=#{message_body.inspect}"
          )
        end

        match
      end

      def request_link_now?(message_body)
        normalized = normalize_inbound_text(message_body)
        normalized == '1'
      end

      def postpone_request?(message_body)
        normalized = normalize_inbound_text(message_body)
        normalized == '2'
      end

      def normalize_inbound_text(message_body)
        message_body.to_s.strip.downcase
      end

      # Builds a "column LIKE ? OR column LIKE ? ..." condition covering every
      # plausible Brazilian "9"-digit variant of normalized_number, so a
      # lookup succeeds regardless of which format the stored value happens
      # to use. For non-Brazilian numbers this is equivalent to a single
      # plain LIKE (unchanged behavior).
      def phone_match_condition(column_sql, normalized_number)
        variants = WhatsApp::PhoneNormalizer.brazil_match_variants(normalized_number)
        sql = variants.map { "#{column_sql} LIKE ?" }.join(' OR ')
        binds = variants.map { |variant| "%#{variant}%" }

        [sql, binds]
      end

      def find_user_by_whatsapp(number)
        normalized_number = normalize_phone(number)
        return nil if normalized_number.blank?

        sql, binds = phone_match_condition(
          "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(whatsapp_number, '+', ''), ' ', ''), '-', ''), '(', ''), ')', '')",
          normalized_number
        )

        candidates = User.where(sql, *binds).to_a
        return nil if candidates.empty?
        return candidates.first if candidates.one?

        # Multiple users share this whatsapp_number. In practice this is
        # usually the same person who signed up more than once with a
        # different email but kept the same phone -- their WhatsApp reply
        # can arrive regardless of which account it "belongs" to. Prefer
        # whichever account most recently received an outbound message,
        # since that's the conversation this reply is most likely
        # continuing, instead of an arbitrary/unordered .first (which
        # previously could pick an account with no outbound history at
        # all and made find_last_outbound miss real history entirely --
        # see find_last_outbound below).
        candidates.max_by do |candidate|
          WhatsappOutbound.where(user_id: candidate.id).maximum(:created_at) || Time.at(0)
        end
      rescue StandardError => e
        Rails.logger.error("[WhatsAppInbound] find_user_by_whatsapp error: #{e.class} - #{e.message}")
        nil
      end

      def find_last_outbound(user, number)
        normalized_number = normalize_phone(number)

        by_user =
          if user.present?
            WhatsappOutbound.where(user_id: user.id).order(created_at: :desc).first
          end

        by_phone =
          if normalized_number.present?
            sql, binds = phone_match_condition('whatsapp_number', normalized_number)
            WhatsappOutbound.where(sql, *binds).order(created_at: :desc).first
          end

        # Previously, finding a user short-circuited to a user_id-only
        # lookup and never considered the phone number at all. When a
        # user's whatsapp_number is duplicated across accounts (or simply
        # isn't the account linked to the actual outbound sends), that
        # user_id lookup can come back empty while a phone-based lookup
        # would have found the real, more recent outbound. Consider both
        # and keep whichever is more recent.
        [by_user, by_phone].compact.max_by(&:created_at)
      rescue StandardError => e
        Rails.logger.error("[WhatsAppInbound] find_last_outbound error: #{e.class} - #{e.message}")
        nil
      end

      def find_or_create_conversation(user:, last_outbound:, inbound_number:, panelist_country:)
        panelist_id = last_outbound&.panelist_id
        project_code = last_outbound&.project_code

        if panelist_id.present? && project_code.present?
          conversation = WhatsappConversation.find_or_initialize_by(
            panelist_id: panelist_id,
            project_code: project_code
          )

          conversation.user = user if user.present?
          conversation.panelist_email = last_outbound&.panelist_email
          conversation.whatsapp_number = inbound_number
          conversation.sample_number = last_outbound&.sample_number
          conversation.support_email = last_outbound&.support_email
          conversation.panelist_country = panelist_country
          conversation.status = 'open'
          conversation.save!

          return conversation
        end

        Rails.logger.info(
          "[WhatsAppInbound] creating_unmatched_conversation from=#{inbound_number} country=#{panelist_country}"
        )

        conversation = WhatsappConversation.find_or_initialize_by(
          project_code: 'UNMATCHED',
          whatsapp_number: inbound_number
        )

        conversation.panelist_id = "unmatched-#{inbound_number.last(6)}" if conversation.panelist_id.blank?

        conversation.user = user if user.present?
        conversation.panelist_email = last_outbound&.panelist_email
        conversation.whatsapp_number = inbound_number
        conversation.sample_number = last_outbound&.sample_number
        conversation.support_email = last_outbound&.support_email
        conversation.panelist_country = panelist_country
        conversation.status = 'open'
        conversation.save!

        conversation
      rescue StandardError => e
        Rails.logger.error("[WhatsAppInbound] find_or_create_conversation error: #{e.class} - #{e.message}")
        nil
      end

      def country_from_phone(phone)
        normalized = normalize_phone(phone)

        COUNTRY_BY_PREFIX.keys.sort_by { |prefix| -prefix.length }.each do |prefix|
          return COUNTRY_BY_PREFIX[prefix] if normalized.start_with?(prefix)
        end

        'Otro'
      end

      def normalize_phone(phone)
        WhatsApp::PhoneNormalizer.normalize(phone)
      end

      def parse_timestamp(timestamp)
        return nil if timestamp.blank?

        Time.at(timestamp.to_i)
      rescue StandardError
        nil
      end

      def opt_out_support_email(phone)
        normalized = normalize_phone(phone)

        base_email =
          if normalized.start_with?('55')
            'suporte@finepanel.net'
          else
            'soporte@finepanel.net'
          end

        [base_email, 'dcasar@fine-research.com'].join(',')
      end

      def opt_out_confirmation_message(phone)
        normalized = normalize_phone(phone)

        if normalized.start_with?('55')
          'Sua solicitação de exclusão de contatos por WhatsApp foi recebida com sucesso. Obrigado.'
        else
          'Su solicitud de exclusión de contactos por WhatsApp fue recibida con éxito. Gracias.'
        end
      end

      def postpone_confirmation_message(phone)
        normalized = normalize_phone(phone)

        if normalized.start_with?('55')
          "Sem problema 👍\n\nEntraremos em contato em outra oportunidade com novos convites.\n\nSe mudar de ideia, é só nos avisar por aqui 😊"
        else
          "No hay problema 👍\n\nLe contactaremos en otra oportunidad cunado contemos con nuevas invitaciones para su especialidad.\n\nSi cambia de idea, puede avisarnos por aquí 😊"
        end
      end

      def request_link_now_message(phone, survey_link)
        normalized = normalize_phone(phone)

        if normalized.start_with?('55')
          "Perfeito 👍\n\nAqui está o link para participar agora:\n#{survey_link}\n\nSe tiver qualquer dúvida, pode nos avisar por aqui."
        else
          "Perfecto 👍\n\nAquí tiene el link para participar ahora:\n#{survey_link}\n\nSi tiene cualquier duda, puede escribirnos por aquí."
        end
      end
    end
  end
end
