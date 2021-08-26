module PostsHelper

  def show_post_by_kind(post)

    case post.kind
    when Post::TYPE[:text]
      render 'posts/types/comment_post', post: post
    when Post::TYPE[:with_image]
      render 'posts/types/image_post', post: post
    when Post::TYPE[:with_video]
      render 'posts/types/video_post', post: post
    when Post::TYPE[:with_document]
      render 'posts/types/document_post', post: post
    end

  end

  def post_body(post, type = :small)
    if type == :small
      truncate(post.text_html, length: 270, omission: "... #{link_to(t("home.read_more"), post_path(post))}").html_safe
    elsif type == :extended
      post.text_html.html_safe
    end
  end

  def support_comment?(user_info)
    complete_name = user_info['complete_name'].downcase
    complete_name.include?('suporte') || complete_name.include?('soporte')
  end

  def support_image(css_class = nil)
    image_tag('icon-support-blue.png', class: css_class || 'support-icon-wall')
  end

  def news_comment?(user)
    user.email && user.email.include?('news')
  end

  def news_image
    content_tag(:div, 'l', :class => 'glyph comment news-glyph')
  end
end
