class NewsConversationReminderMailer < ApplicationMailer
  include MailersHelper

  TEMPLATE_IDS = {
    reminder: 'd-2c12dc1deb784f54ad565a3147cdab24',
    first_reply: 'd-e73f18ba2c3448a894766bc0329e9224',
    comment_agreement: 'd-e20daba5283d43a180babd0dfa900aa4',
    # Reusa el template de first_reply a proposito -- mismo layout, mismas
    # variables (subject/heading/body/cta/cta_url), el contenido real sigue
    # siendo distinto porque se inyecta en runtime via dynamic_template_data.
    # Unico costo: las estadisticas de apertura de SendGrid quedan mezcladas
    # entre first_reply y comment_reply (decision del usuario 2026-09-19).
    comment_reply: 'd-e73f18ba2c3448a894766bc0329e9224'
  }.freeze

  FROM = "comentarios@finepanel.net"

  def comment_reply_email(recipient_email, locale, news_feed, user)
    mail = generate_email(TEMPLATE_IDS[:comment_reply], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.comment_reply.subject', locale: locale),
      heading: I18n.t('mailers.comment_reply.heading', locale: locale),
      body: I18n.t('mailers.comment_reply.body', locale: locale, title: title_for(news_feed, locale)),
      cta: I18n.t('mailers.comment_reply.cta', locale: locale),
      cta_url: conversation_url(news_feed, user, recipient_email),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  def comment_agreement_email(recipient_email, locale, news_feed, user)
    mail = generate_email(TEMPLATE_IDS[:comment_agreement], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.comment_agreement.subject', locale: locale),
      heading: I18n.t('mailers.comment_agreement.heading', locale: locale),
      body: I18n.t('mailers.comment_agreement.body', locale: locale, title: title_for(news_feed, locale)),
      cta: I18n.t('mailers.comment_agreement.cta', locale: locale),
      cta_url: conversation_url(news_feed, user, recipient_email),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  def first_reply_email(recipient_email, locale, news_feed, user)
    mail = generate_email(TEMPLATE_IDS[:first_reply], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.first_comment_reply.subject', locale: locale),
      heading: I18n.t('mailers.first_comment_reply.heading', locale: locale),
      body: I18n.t('mailers.first_comment_reply.body', locale: locale, title: title_for(news_feed, locale)),
      cta: I18n.t('mailers.first_comment_reply.cta', locale: locale),
      cta_url: conversation_url(news_feed, user, recipient_email),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  def reminder_email(recipient_email, locale, news_feed, countries, user)
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
      cta_url: conversation_url(news_feed, user, recipient_email),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  private

  # Link de auto-login cuando el destinatario tiene los datos necesarios
  # (mismo mecanismo ya usado por los links de encuestas/paneles -- ver
  # UsersRedirect.js en el frontend). "t" lleva el id de la noticia para
  # que, despues de loguear (o de comprobar que ya habia sesion), el
  # frontend pueda reconstruir el link directo con el hash de siempre. Cae
  # al link plano de siempre si al usuario le falta spanel/encrypted_email,
  # para nunca romper el envio del mail por esto.
  def conversation_url(news_feed, user, email)
    base = ENV.fetch('WEB_APP_HOST', 'https://finepanel.net')

    return "#{base}/dashboard/news#news_#{news_feed.id}" unless user&.encrypted_email.present? && user&.spanel.present?

    respid = user.user_respid(email)
    "#{base}/users/redirect_user_login?e=#{user.encrypted_email}&r=#{respid}&s=#{user.spanel}&t=#{news_feed.id}"
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
