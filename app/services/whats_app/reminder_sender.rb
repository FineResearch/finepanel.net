# app/services/whats_app/reminder_sender.rb

module WhatsApp
  class ReminderSender
    def initialize(project_code:, panelist_ids:, text_es:, text_pt:, internal_user:)
      @project_code = project_code.to_s.strip
      @panelist_ids = Array(panelist_ids).map { |id| id.to_s.strip }.reject(&:blank?).uniq
      @text_es = text_es.to_s.strip
      @text_pt = text_pt.to_s.strip
      @internal_user = internal_user
      @client = WhatsApp::Client.new
    end

    def run
      results = {
        sent_free_text: [],
        sent_template: [],
        skipped: []
      }

      conversations.find_each do |conversation|
        begin
          unless eligible?(conversation)
            results[:skipped] << {
              panelist_id: conversation.panelist_id,
              reason: 'not_eligible'
            }
            next
          end

          if conversation.within_customer_care_window?
            send_free_text(conversation, results)
          else
            send_template(conversation, results)
          end
        rescue => e
          Rails.logger.error("[ReminderSender] error panelist=#{conversation.panelist_id} #{e.class} #{e.message}")
          results[:skipped] << {
            panelist_id: conversation.panelist_id,
            reason: "#{e.class} - #{e.message}"
          }
        end
      end

      results
    end

    private

    def conversations
      WhatsappConversation.where(
        project_code: @project_code,
        panelist_id: @panelist_ids
      )
    end

    def eligible?(conversation)
      wpp = WhatsappProjectPanelist.find_by(
        project_code: @project_code,
        panelist_id: conversation.panelist_id
      )

      return false if wpp.blank?
      return false if wpp.status.to_s == 'cancelled'
      return false if wpp.status.to_s.include?('completed')

      inbound = last_inbound(conversation)
      return false if inbound.blank?
      return false unless inbound.message_body.to_s.strip == '1'
      return false if newer_inbound_exists?(conversation, inbound)

      true
    end

    def last_inbound(conversation)
      conversation.whatsapp_messages
                  .where(direction: 'inbound')
                  .order(created_at: :desc)
                  .first
    end

    def newer_inbound_exists?(conversation, inbound)
      conversation.whatsapp_messages
                  .where(direction: 'inbound')
                  .where("created_at > ?", inbound.created_at)
                  .exists?
    end

    def send_free_text(conversation, results)
      text = resolve_free_text(conversation)
      return if text.blank?

      to_number = resolve_whatsapp_number(conversation)
      return if to_number.blank?

      phone_number_id = resolve_phone_number_id(to_number)

      @client.send_text_message(
        phone_number_id: phone_number_id,
        to_number: to_number,
        body: text
      )

      create_outbound_log(
        conversation: conversation,
        status: 'sent',
        template_name: nil,
        language: resolve_language(to_number)
      )

      conversation.whatsapp_messages.create!(
        direction: 'outbound',
        source: 'agent',
        internal_user: @internal_user,
        message_body: text
      )

      conversation.touch_outbound!

      results[:sent_free_text] << conversation.panelist_id
    end

    def send_template(conversation, results)
      to_number = resolve_whatsapp_number(conversation)
      return if to_number.blank?

      language = resolve_language(to_number)
      template_name = resolve_template_name(language)
      phone_number_id = resolve_phone_number_id(to_number)

      @client.send_message(
        phone_number_id: phone_number_id,
        to_number: to_number,
        template: template_name,
        language: language,
        parameters: build_template_params(conversation, language)
      )

      create_outbound_log(
        conversation: conversation,
        status: 'sent',
        template_name: template_name,
        language: language
      )

      conversation.whatsapp_messages.create!(
        direction: 'outbound',
        source: 'template',
        internal_user: @internal_user,
        message_body: nil,
        template_name: template_name,
        template_language: language
      )

      conversation.touch_outbound!

      results[:sent_template] << conversation.panelist_id
    end

    def resolve_free_text(conversation)
      number = resolve_whatsapp_number(conversation)
      return nil if number.blank?

      language = resolve_language(number)
      provided_text = language == 'pt_BR' ? @text_pt : @text_es

      return provided_text if provided_text.present?

      default_free_text(conversation, language)
    end

    def default_free_text(conversation, language)
  greeting = "#{manual_greeting_title(conversation)} #{manual_greeting_name(conversation)}".strip

  if language == 'pt_BR'
    "Olá #{greeting}, gostaríamos de saber se precisa de ajuda para participar do estudo. Estamos por aqui para ajudar no que precisar."
  else
    "Hola #{greeting}, queríamos ver si necesita ayuda para participar del estudio. Por cualquier duda estamos por aquí para ayudarle."
  end
end

def manual_greeting_title(conversation)
  user = conversation.respond_to?(:user) ? conversation.user : nil
  title = user&.professional_title.to_s.strip

  return title if title.present?

  'Dr(a).'
end

def manual_greeting_name(conversation)
  user = conversation.respond_to?(:user) ? conversation.user : nil

  name =
    user&.first_name.presence ||
    user&.last_name.presence ||
    'Doctor(a)'

  name.to_s.strip
end
    def default_greeting_name(conversation)
  title = resolved_professional_title(conversation)
  name = resolved_person_name(conversation, resolve_language(resolve_whatsapp_number(conversation)))

  return title if name.blank?

  "#{title} #{name}".strip
end

def build_template_params(conversation, language)
  [
    { type: 'text', text: manual_greeting_title(conversation) },
    { type: 'text', text: manual_greeting_name(conversation) }
  ]
end

def manual_greeting_title(conversation)
  user = conversation.respond_to?(:user) ? conversation.user : nil
  title = user&.professional_title.to_s.strip

  return title if title.present?

  'Dr(a).'
end

def manual_greeting_name(conversation)
  user = conversation.respond_to?(:user) ? conversation.user : nil

  name =
    user&.first_name.presence ||
    user&.last_name.presence ||
    'Doctor(a)'

  name.to_s.strip
end

def resolved_professional_title(conversation)
  user = User.find_by(id: conversation.panelist_id)
  title = user&.professional_title.to_s.strip

  return title if title.present?

  'Dr(a).'
end

def resolved_person_name(conversation, language)
  user = User.find_by(id: conversation.panelist_id)
  outbound = conversation.related_outbounds.order(created_at: :desc).first

  candidates =
    if language == 'pt_BR'
      [
        outbound_value(outbound, :panelist_first_name, :first_name),
        outbound_value(outbound, :panelist_last_name, :last_name),
        user&.first_name.to_s.strip.presence,
        user&.last_name.to_s.strip.presence
      ]
    else
      [
        outbound_value(outbound, :panelist_first_name, :first_name),
        outbound_value(outbound, :panelist_last_name, :last_name),
        user&.first_name.to_s.strip.presence,
        user&.last_name.to_s.strip.presence
      ]
    end

  candidates.compact.map(&:to_s).map(&:strip).find(&:present?)
end


    def outbound_value(outbound, *candidate_fields)
      return nil if outbound.blank?

      candidate_fields.each do |field_name|
        field_key = field_name.to_s

        if outbound.respond_to?(:has_attribute?) && outbound.has_attribute?(field_key)
          value = outbound[field_key]
          return value.to_s.strip if value.present?
        end

        next unless outbound.respond_to?(field_name)

        value = outbound.public_send(field_name)
        return value.to_s.strip if value.present?
      end

      nil
    end

    def resolve_template_name(language)
      language == 'pt_BR' ? 'reminder_support_v1' : 'reminder_support_v1_es'
    end

    def resolve_language(number)
      brazil?(number) ? 'pt_BR' : 'es_MX'
    end

    def brazil?(number)
      number.to_s.start_with?('55')
    end

    def resolve_whatsapp_number(conversation)
      outbound = conversation.related_outbounds.order(created_at: :desc).first
      WhatsApp::PhoneNormalizer.normalize(outbound&.whatsapp_number)
    end

    def resolve_survey_link(conversation)
      outbound = conversation.related_outbounds.order(created_at: :desc).first
      link = outbound&.main_survey_link.presence || outbound&.survey_link.presence

      return link if link.present?

      wpp = WhatsappProjectPanelist.find_by(
        project_code: conversation.project_code,
        panelist_id: conversation.panelist_id
      )

      wpp&.tracked_survey_link.presence || wpp&.original_survey_link.to_s
    end

    def resolve_phone_number_id(phone)
      normalized_phone = phone.to_s.gsub(/\D/, '')
      default_id = ENV['WHATSAPP_US_NUMBER_ID'] || ENV['WHATSAPP_ID_NUMBER']

      case
      when normalized_phone.start_with?('55')
        ENV['WHATSAPP_BR_NUMBER_ID'] || default_id
      when normalized_phone.start_with?('52')
        ENV['WHATSAPP_MX_NUMBER_ID'] || default_id
      when normalized_phone.start_with?('57')
        ENV['WHATSAPP_CO_NUMBER_ID'] || default_id
      when normalized_phone.start_with?('54')
        ENV['WHATSAPP_AR_NUMBER_ID'] || default_id
      else
        default_id
      end
    end

   

    def create_outbound_log(conversation:, status:, template_name:, language:)
      attrs = {
        panelist_id: conversation.panelist_id,
        project_code: conversation.project_code,
        whatsapp_number: resolve_whatsapp_number(conversation),
        status: status,
        template_name: template_name,
        language: language,
        sent_by: @internal_user&.email
      }

      WhatsappOutbound.create!(attrs)
    rescue => e
      Rails.logger.error("[ReminderSender] outbound_log_error panelist=#{conversation.panelist_id} #{e.class} #{e.message}")
    end
  end
end
