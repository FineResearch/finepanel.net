require 'rails_helper'

RSpec.describe 'WhatsApp inbound webhook matching', type: :request do
  def inbound_payload(from:, text: 'Hola')
    {
      entry: [
        {
          changes: [
            {
              value: {
                contacts: [{ wa_id: from, profile: { name: 'Panelista' } }],
                messages: [
                  {
                    from: from,
                    type: 'text',
                    text: { body: text },
                    id: "wamid.#{SecureRandom.hex(8)}",
                    timestamp: Time.current.to_i.to_s
                  }
                ],
                metadata: { phone_number_id: '1234567890', display_phone_number: '5511999999999' }
              }
            }
          ]
        }
      ]
    }
  end

  def create_user!(whatsapp_number:, jti: SecureRandom.uuid)
    User.create!(
      encrypted_email: Digest::MD5.hexdigest("#{whatsapp_number}-#{jti}"),
      whatsapp_number: whatsapp_number,
      jti: jti
    )
  end

  def create_outbound!(user:, whatsapp_number:, project_code:, panelist_id: rand(1000..9999))
    WhatsappOutbound.create!(
      user: user,
      whatsapp_number: whatsapp_number,
      project_code: project_code,
      panelist_id: panelist_id,
      status: 'sent',
      template_name: 'survey_invitation_reply_v1',
      created_at: 1.day.ago
    )
  end

  describe 'Brazilian mobile number missing the "9" digit' do
    it 'matches an existing conversation even when Meta sends the number without the 9' do
      user = create_user!(whatsapp_number: '+5591987097562')
      create_outbound!(user: user, whatsapp_number: '5591987097562', project_code: 'FP-18452')

      # Meta sends the inbound wa_id without the "9" after the DDD.
      post '/api/v1/webhooks/handle_whatsapp_response', params: inbound_payload(from: '559187097562').to_json,
                                                          headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('FP-18452')
      expect(conversation.panelist_id).not_to start_with('unmatched-')
    end

    it 'still matches when Meta sends the number already including the 9 (unchanged behavior)' do
      user = create_user!(whatsapp_number: '+5591987097562')
      create_outbound!(user: user, whatsapp_number: '5591987097562', project_code: 'FP-18452')

      post '/api/v1/webhooks/handle_whatsapp_response', params: inbound_payload(from: '5591987097562').to_json,
                                                          headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('FP-18452')
    end
  end

  describe 'duplicate users sharing the same whatsapp_number' do
    it 'still finds the real outbound history via phone number when the matched user has none' do
      real_user = create_user!(whatsapp_number: '+5521984962352')
      create_outbound!(user: real_user, whatsapp_number: '5521984962352', project_code: 'FF-18655')

      # A second, unrelated user record with the exact same whatsapp_number
      # and no outbound history at all -- this is the duplicate-account
      # scenario found in production.
      create_user!(whatsapp_number: '+5521984962352')

      post '/api/v1/webhooks/handle_whatsapp_response', params: inbound_payload(from: '5521984962352').to_json,
                                                          headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('FF-18655')
      expect(conversation.panelist_id).not_to start_with('unmatched-')
    end

    it 'when both duplicate accounts received outbounds, picks the one with the most recent message' do
      older_account = create_user!(whatsapp_number: '+5521984962352')
      create_outbound!(
        user: older_account,
        whatsapp_number: '5521984962352',
        project_code: 'OLD-PROJECT'
      ).update!(created_at: 30.days.ago)

      newer_account = create_user!(whatsapp_number: '+5521984962352')
      create_outbound!(
        user: newer_account,
        whatsapp_number: '5521984962352',
        project_code: 'NEW-PROJECT'
      ).update!(created_at: 1.day.ago)

      post '/api/v1/webhooks/handle_whatsapp_response', params: inbound_payload(from: '5521984962352').to_json,
                                                          headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('NEW-PROJECT')
    end
  end

  describe 'Mexican mobile number with the extra "1"' do
    it 'still matches after normalization (existing behavior, unaffected by the Brazil fix)' do
      user = create_user!(whatsapp_number: '+525512345678')
      create_outbound!(user: user, whatsapp_number: '525512345678', project_code: 'MX-1000')

      # Meta sends the inbound wa_id with the "1" mobile prefix.
      post '/api/v1/webhooks/handle_whatsapp_response', params: inbound_payload(from: '5215512345678').to_json,
                                                          headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('MX-1000')
    end
  end

  describe 'a genuinely unmatched inbound message' do
    it 'is preserved as UNMATCHED without using the raw phone number as panelist_id' do
      post '/api/v1/webhooks/handle_whatsapp_response',
           params: inbound_payload(from: '5511900000000').to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)

      conversation = WhatsappConversation.order(:created_at).last
      expect(conversation.project_code).to eq('UNMATCHED')
      expect(conversation.panelist_id).to start_with('unmatched-')
    end
  end
end
