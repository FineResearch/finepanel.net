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
  def dynamic_template_data_for(user, locale: 'es')
    sent_mail = nil
    allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

    described_class.new.comment_reply_email('author@example.com', locale, news_feed, user)

    JSON.parse(sent_mail.to_json).dig('personalizations', 0, 'dynamic_template_data')
  end

  def social_discovery_data_for(user, locale: 'es', useful_count: 10)
    sent_mail = nil
    allow_any_instance_of(described_class).to receive(:send_email) { |_, mail| sent_mail = mail }

    described_class.new.news_social_discovery_email('reader@example.com', locale, news_feed, user, useful_count)

    JSON.parse(sent_mail.to_json).dig('personalizations', 0, 'dynamic_template_data')
  end

  def cta_url_for(user)
    dynamic_template_data_for(user)['cta_url']
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

  describe 'unsubscribe_url / unsubscribe_label' do
    let(:user) do
      User.create!(encrypted_email: Digest::MD5.hexdigest('author@example.com'), jti: SecureRandom.uuid)
    end

    it 'incluye un link firmado al endpoint de unsubscribe, en espanol por default' do
      data = dynamic_template_data_for(user)

      expect(data['unsubscribe_url']).to start_with('https://finepanel.net/notifications/unsubscribe?token=')
      expect(data['unsubscribe_label']).to eq('Cancelar suscripción a estos avisos')

      token = data['unsubscribe_url'].split('token=').last
      expect(User.find_from_unsubscribe_token(token)).to eq(user)
    end

    it 'usa el prefijo /pt y el copy en portugues cuando locale es pt' do
      data = dynamic_template_data_for(user, locale: 'pt')

      expect(data['unsubscribe_url']).to start_with('https://finepanel.net/pt/notifications/unsubscribe?token=')
      expect(data['unsubscribe_label']).to eq('Descadastrar-se destes avisos')
    end

    it 'no genera link cuando no hay usuario' do
      data = dynamic_template_data_for(nil)

      expect(data['unsubscribe_url']).to be_nil
    end
  end

  describe '#news_social_discovery_email' do
    let(:user) do
      User.create!(encrypted_email: Digest::MD5.hexdigest('reader@example.com'), jti: SecureRandom.uuid)
    end

    it 'usa el copy en espanol y el conteo pasado como snapshot' do
      data = social_discovery_data_for(user, locale: 'es', useful_count: 14)

      expect(data['subject']).to eq("Actualización: #{news_feed.title}")
      expect(data['heading']).to eq(news_feed.title)
      expect(data['body']).to eq('14 colegas de tu especialidad encontraron útil esta actualización y ya están comentando sobre ella.')
      expect(data['cta']).to eq('VER ACTUALIZACIÓN Y DISCUSIÓN')
    end

    it 'usa el copy en portugues cuando el locale es pt' do
      data = social_discovery_data_for(user, locale: 'pt', useful_count: 14)

      expect(data['subject']).to eq("Atualização: #{news_feed.title}")
      expect(data['body']).to eq('14 colegas da sua especialidade acharam esta atualização útil e já estão comentando sobre ela.')
      expect(data['cta']).to eq('VER ATUALIZAÇÃO E DISCUSSÃO')
    end

    it 'cae al texto plano de la noticia como teaser cuando no hay fine_news_summary' do
      data = social_discovery_data_for(user)

      expect(data['teaser']).to eq(news_feed.text)
    end
  end
end
