require 'rails_helper'

RSpec.describe NewsConversationReminderMailer do
  let(:specialty) { Specialty.create!(name: 'Cardiologia', slug: "cardiologia-#{SecureRandom.hex(4)}") }
  let(:article) do
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'Articulo de prueba',
      slug: "/topics/test-#{SecureRandom.hex(4)}",
      specialty: specialty,
    )
  end
  let(:news_feed) { NewsFeed.create!(text: "texto de la noticia #{SecureRandom.hex(4)}", specialty: specialty, article: article) }

  # ENV.fetch('WEB_APP_HOST', ...) cae al default cuando la var no esta
  # seteada en el entorno de test -- se fija explicitamente para que el
  # assert del host no dependa de que .env este cargado o no.
  around do |example|
    original = ENV['WEB_APP_HOST']
    ENV['WEB_APP_HOST'] = 'https://finepanel.net'
    example.run
    ENV['WEB_APP_HOST'] = original
  end

  # cta_url se arma adentro de conversation_url (privado) -- se verifica via
  # el payload real que se manda a SendGrid, capturando el mail ANTES de
  # que send_email intente pegarle a la red (send_email queda stubbeado).
  # Se llama a la instancia directo (no via la clase, que en ActionMailer
  # devuelve un MessageDelivery diferido) para ejecutar el metodo ya mismo.
  def cta_url_for(user)
    sent_mail = nil
    allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

    described_class.new.comment_reply_email('author@example.com', 'es', news_feed, user)

    JSON.parse(sent_mail.to_json).dig('personalizations', 0, 'dynamic_template_data', 'cta_url')
  end

  describe '#comment_reply_email' do
    it 'genera un link de auto-login cuando el usuario tiene spanel y encrypted_email' do
      user = User.create!(
        encrypted_email: Digest::MD5.hexdigest('author@example.com'),
        spanel: 'PANEL123',
        hash_respid: '999999',
        jti: SecureRandom.uuid,
      )

      cta_url = cta_url_for(user)

      expect(cta_url).to start_with('https://finepanel.net/users/redirect_user_login?')
      expect(cta_url).to include("e=#{user.encrypted_email}")
      expect(cta_url).to include('s=PANEL123')
      expect(cta_url).to include("t=#{news_feed.id}")
    end

    it 'cae al link plano cuando el usuario no tiene spanel' do
      user = User.create!(
        encrypted_email: Digest::MD5.hexdigest('author@example.com'),
        spanel: nil,
        jti: SecureRandom.uuid,
      )

      expect(cta_url_for(user)).to eq("https://finepanel.net/dashboard/news#news_#{news_feed.id}")
    end

    it 'cae al link plano cuando no hay usuario' do
      expect(cta_url_for(nil)).to eq("https://finepanel.net/dashboard/news#news_#{news_feed.id}")
    end
  end
end
