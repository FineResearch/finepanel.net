class NewsCommentMailer < ApplicationMailer
  include MailersHelper

  TEMPLATE_IDS = {
    new_comment: 'd-0980ee1d2e624aa08c23512f81d8ea5b'
  }

  FROM = "comentarios@finepanel.net"
  TO = "comentarios@finepanel.net"

  def news_comment_email(comment, respid)
    mail = generate_email(TEMPLATE_IDS[:new_comment], FROM)
    personalization = generate_personalization(TO)

    personalization.add_dynamic_template_data({
      complete_name: comment.user_info['complete_name'],
      country: comment.user_info['country'],
      text: comment.text,
      respid: respid,
      email: comment.user_info['email'],
      delete_url: Rails.application.routes.url_helpers.delete_api_v1_news_comment_url(comment.id, host: resolve_host)
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end
end
