class NewsCommentReminderWorker
  include Sidekiq::Worker

  MIN_SUBSEQUENT_COMMENTS = 3
  MIN_DISTINCT_AUTHORS = 2
  NOTIFICATION_TYPE = Notification::TYPES[:news_conversation_reminder]

  def perform(news_feed_id)
    news_feed = NewsFeed.find_by(id: news_feed_id)
    return unless news_feed.present?

    comments = news_feed.news_comments.order(:created_at).to_a
    return if comments.size < MIN_SUBSEQUENT_COMMENTS + 1

    comments.group_by(&:user_id).each do |candidate_user_id, candidate_comments|
      process_candidate(news_feed, comments, candidate_user_id, candidate_comments)
    end
  end

  private

  def process_candidate(news_feed, comments, candidate_user_id, candidate_comments)
    return if already_notified?(candidate_user_id, news_feed.id)

    baseline_time = candidate_comments.map(&:created_at).max
    subsequent = comments.select do |comment|
      comment.created_at > baseline_time && comment.user_id != candidate_user_id
    end

    return if subsequent.size < MIN_SUBSEQUENT_COMMENTS
    return if subsequent.map(&:user_id).uniq.size < MIN_DISTINCT_AUTHORS

    candidate_user_info = candidate_comments.max_by(&:created_at).user_info
    send_reminder(candidate_user_id, candidate_user_info, news_feed, subsequent)
  end

  def already_notified?(user_id, news_feed_id)
    Notification.exists?(
      user_id: user_id,
      news_feed_id: news_feed_id,
      notification_type: NOTIFICATION_TYPE,
    )
  end

  # Reserva la notificacion primero (la unicidad a nivel DB protege contra
  # el caso de dos jobs corriendo en simultaneo para la misma noticia) y
  # recien despues encola el mail, para nunca enviar dos veces al mismo
  # usuario aunque el registro de la notificacion falle por alguna razon.
  def send_reminder(user_id, user_info, news_feed, subsequent_comments)
    begin
      Notification.create!(
        user_id: user_id,
        news_feed_id: news_feed.id,
        notification_type: NOTIFICATION_TYPE,
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return
    end

    return unless user_info.present? && user_info['email'].present?

    user = User.find_by(id: user_id)
    return if user&.comment_notifications_opt_out?

    countries = subsequent_comments.map { |comment| comment.user_info['country'] }.compact.uniq
    locale = resolve_locale(user)

    NewsConversationReminderMailer.reminder_email(
      user_info['email'],
      locale,
      news_feed,
      countries,
      user,
    ).deliver_later
  end

  def resolve_locale(user)
    return 'es' unless user.present?

    user.language == 'por' ? 'pt' : 'es'
  end
end
