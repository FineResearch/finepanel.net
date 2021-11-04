class PostMailer < ApplicationMailer
  include MailersHelper

  TEMPLATE_IDS = {
    new_post: 'd-8a8150ba40264ab6a0358173159a194e'
  }

  FROM = "comentarios@finepanel.net"
  TO = "comentarios@finepanel.net"

  def new_post_email(post, respid)
    mail = generate_email(TEMPLATE_IDS[:new_post], FROM)
    personalization = generate_personalization(TO)

    personalization.add_dynamic_template_data({
      complete_name: post.user_info['complete_name'],
      country: post.user_info['country'],
      text: post.text,
      respid: respid,
      email: post.user_info['email'],
      delete_url: Rails.application.routes.url_helpers.delete_api_v1_post_url(post.id, host: resolve_host)
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end
end
