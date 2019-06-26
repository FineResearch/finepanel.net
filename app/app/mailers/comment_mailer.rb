class CommentMailer < ActionMailer::Base
  default from: "comentarios@finepanel.net <comentarios@finepanel.net>"

  def new_comment_email(comment, respid)
    @comment = comment
    @respid = respid
    mail(:to => "comentarios@finepanel.net", :subject => "Nuevo post en FinePanel")
  end

  def new_comment_email_for_participants(comment, recipients)
    self.message.perform_deliveries = false
    @comment = comment
    mail(:bcc => recipients, :subject => t("posts.mailer_subject"))
  end
end