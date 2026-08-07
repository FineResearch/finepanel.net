class NewsConversationReminderMailer < ApplicationMailer
  include MailersHelper

  TEMPLATE_IDS = {
    reminder: 'd-2c12dc1deb784f54ad565a3147cdab24'
  }.freeze

  FROM = "comentarios@finepanel.net"

  def reminder_email(recipient_email, locale, news_feed, countries)
    mail = generate_email(TEMPLATE_IDS[:reminder], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.news_conversation_reminder.subject', locale: locale),
      heading: I18n.t('mailers.news_conversation_reminder.heading', locale: locale),
      intro: I18n.t('mailers.news_conversation_reminder.intro', locale: locale),
      title: title_for(news_feed, locale),
      invite: I18n.t('mailers.news_conversation_reminder.invite', locale: locale),
      countries_text: countries_text(countries, locale),
      cta: I18n.t('mailers.news_conversation_reminder.cta', locale: locale),
      cta_url: conversation_url(news_feed),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  private

  def conversation_url(news_feed)
    "#{ENV.fetch('WEB_APP_HOST', 'https://finepanel.net')}/dashboard/news#news_#{news_feed.id}"
  end

  # Prioriza el titulo editorial (fine_news_summary) traducido al idioma
  # del destinatario si existe, y cae al titulo legacy traducido o al
  # titulo original si no hay traduccion disponible para ese idioma.
  def title_for(news_feed, locale)
    if news_feed.fine_news_summary.present?
      translated_title = news_feed.fine_news_summary_translations&.dig(locale, 'editorial_content', 'title')
      return translated_title if translated_title.present?

      original_title = news_feed.fine_news_summary.dig('editorial_content', 'title')
      return original_title if original_title.present?
    end

    translation = news_feed.news_feed_translations.find_by(locale: locale)

    translation&.title || news_feed.title
  end

  def countries_text(countries, locale)
    return nil if countries.blank?

    I18n.t('mailers.news_conversation_reminder.countries', locale: locale, countries: countries.join(', '))
  end
end
