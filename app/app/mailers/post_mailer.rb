class PostMailer < ActionMailer::Base
  default from: "comentarios@finepanel.net <comentarios@finepanel.net>"

  def new_post_email(post, respid)
    @post = post
    @respid = respid
    mail(:to => "comentarios@finepanel.net", :subject => "Nuevo post en FinePanel")
  end
end
