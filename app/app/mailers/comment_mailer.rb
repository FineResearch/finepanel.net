class CommentMailer < ApplicationMailer
  TEMPLATE_IDS = {
    new_comment_participants: 'd-47d13bcbd6d643a8b95415fdaa20c684',
    new_comment: 'd-0beaeb01e336406291026237df6ebfd4'
  }

  FROM = "comentarios@finepanel.net"
  TO = "comentarios@finepanel.net"

  def new_comment_email(comment, respid)
    mail = generate_email(TEMPLATE_IDS[:new_comment], FROM)
    personalization = generate_personalization(TO)
    personalization.add_dynamic_template_data({
      complete_name: comment.user_info['complete_name'],
      country: comment.user_info['country'],
      text: comment.text,
      respid: respid,
      email: comment.user_info['email'],
      delete_url: Rails.application.routes.url_helpers.delete_comment_url(comment.id, locale: :es, host: 'finepanel.net')
    })

    mail.add_personalization(personalization)

    send_email(mail)
  end

  def new_comment_email_for_participants(comment, recipients)
    mail = generate_email(TEMPLATE_IDS[:new_comment_participants], FROM)

    recipients.each do |recipient|
      personalization = generate_personalization(recipient)

      personalization.add_dynamic_template_data({
        subject: I18n.t("posts.mailer_subject"),
        first_paragraph: I18n.t('mailers.new_comment.p1_1', colleague_name: comment.user_info['complete_name']),
        second_paragraph: I18n.t('mailers.new_comment.p1_2', post_text: comment.post.text),
        signature: I18n.t('mailers.new_comment.signature')
      })

      mail.add_personalization(personalization)
    end

    send_email(mail)
  end
end
