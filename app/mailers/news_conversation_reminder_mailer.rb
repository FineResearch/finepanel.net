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
    comment_reply: 'd-e73f18ba2c3448a894766bc0329e9224',
    # Template propio (no reusa otro) para poder trackear este tipo de
    # aviso por separado en las estadisticas de apertura de SendGrid.
    news_social_discovery: 'd-3c87e491af7743cfbafe9f654696f4b1'
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
      unsubscribe_label: I18n.t('mailers.unsubscribe_label', locale: locale),
      unsubscribe_url: unsubscribe_url(user, locale),
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
      unsubscribe_label: I18n.t('mailers.unsubscribe_label', locale: locale),
      unsubscribe_url: unsubscribe_url(user, locale),
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
      unsubscribe_label: I18n.t('mailers.unsubscribe_label', locale: locale),
      unsubscribe_url: unsubscribe_url(user, locale),
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
      unsubscribe_label: I18n.t('mailers.unsubscribe_label', locale: locale),
      unsubscribe_url: unsubscribe_url(user, locale),
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  # Aviso de "descubrimiento social": util_count es un snapshot fijado una
  # sola vez cuando se reserva la campana (NewsSocialDiscoveryService), no
  # un conteo recalculado en caliente -- asi el numero es el mismo para
  # todos los destinatarios de una misma corrida aunque el conteo real
  # siga subiendo mientras el worker procesa la lista.
  def news_social_discovery_email(recipient_email, locale, news_feed, user, useful_count)
    mail = generate_email(TEMPLATE_IDS[:news_social_discovery], FROM)
    personalization = generate_personalization(recipient_email)

    personalization.add_dynamic_template_data({
      subject: I18n.t('mailers.news_social_discovery.subject', locale: locale, title: title_for(news_feed, locale)),
      heading: title_for(news_feed, locale),
      teaser: teaser_for(news_feed, locale),
      body: I18n.t('mailers.news_social_discovery.body', locale: locale, count: useful_count),
      cta: I18n.t('mailers.news_social_discovery.cta', locale: locale),
      cta_url: conversation_url(news_feed, user, recipient_email),
      unsubscribe_label: I18n.t('mailers.unsubscribe_label', locale: locale),
      unsubscribe_url: unsubscribe_url(user, locale),
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

  # Link de un click para darse de baja SOLO de estos avisos de comentarios
  # (no del resto de FinePanel, eso lo maneja Forsta aparte). nil si no hay
  # user -- el helper de la vista/template de SendGrid decide que hacer
  # con un link vacio, pero en la practica user siempre esta presente aca.
  def unsubscribe_url(user, locale)
    return nil unless user.present?

    base = ENV.fetch('WEB_APP_HOST', 'https://finepanel.net')
    path_prefix = locale == 'pt' ? '/pt' : ''
    "#{base}#{path_prefix}/notifications/unsubscribe?token=#{user.comment_notifications_unsubscribe_token}"
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

  # Mismo patron de fallback que title_for, pero para el teaser del mail
  # de descubrimiento social -- usa el primer bloque editorial (lo mas
  # parecido a un resumen corto en fine_news_summary), cae al texto plano
  # de siempre para articulos en formato viejo sin fine_news_summary.
  def teaser_for(news_feed, locale)
    if news_feed.fine_news_summary.present?
      translated_teaser = news_feed.fine_news_summary_translations&.dig(locale, 'editorial_content', 'what_this_evidence_shows')
      return translated_teaser if translated_teaser.present?

      original_teaser = news_feed.fine_news_summary.dig('editorial_content', 'what_this_evidence_shows')
      return original_teaser if original_teaser.present?
    end

    news_feed.text
  end

  def countries_text(countries, locale)
    return nil if countries.blank?

    I18n.t('mailers.news_conversation_reminder.countries', locale: locale, countries: countries.join(', '))
  end
end
