require 'rails_helper'

RSpec.describe CommentAgreementNotificationWorker do
  let(:specialty) { Specialty.create!(name: 'Cardiologia', slug: "cardiologia-#{SecureRandom.hex(4)}") }
  let(:article) do
    Article.create!(
      dynamed_id: "DM-#{SecureRandom.hex(4)}",
      title: 'Articulo de prueba',
      slug: "/topics/test-#{SecureRandom.hex(4)}",
      specialty: specialty,
    )
  end
  let(:news_feed) { NewsFeed.create!(text: "texto de la noticia #{SecureRandom.hex(4)}", specialty: specialty, article: article) }
  let(:author) { create_user('author@example.com') }
  let(:reactor_a) { create_user('a@example.com') }
  let(:reactor_b) { create_user('b@example.com') }
  let(:reactor_c) { create_user('c@example.com') }

  let(:comment) do
    NewsComment.create!(
      text: 'comentario de prueba',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )
  end

  subject(:perform) { described_class.new.perform(comment.id) }

  before do
    allow(NewsConversationReminderMailer).to receive(:comment_agreement_email).and_return(double(deliver_later: true))
  end

  def create_user(email)
    User.create!(encrypted_email: Digest::MD5.hexdigest(email), jti: SecureRandom.uuid)
  end

  def react(user)
    NewsCommentReaction.create!(user: user, news_comment: comment)
  end

  it 'notifies the comment author once 2 distinct colleagues have reacted' do
    react(reactor_a)
    react(reactor_b)

    perform

    expect(NewsConversationReminderMailer).to have_received(:comment_agreement_email).once.with(
      'author@example.com', 'es', news_feed
    )
    expect(
      Notification.exists?(user: author, news_feed: news_feed, notification_type: 'comment_agreement', news_comment: comment)
    ).to be true
  end

  it 'does not notify with only 1 reactor' do
    react(reactor_a)

    perform

    expect(NewsConversationReminderMailer).not_to have_received(:comment_agreement_email)
    expect(Notification.count).to eq(0)
  end

  it 'never sends more than one notification for the same comment, even if run again' do
    react(reactor_a)
    react(reactor_b)

    perform
    perform

    expect(NewsConversationReminderMailer).to have_received(:comment_agreement_email).once
    expect(Notification.where(user: author, news_feed: news_feed, notification_type: 'comment_agreement', news_comment: comment).count).to eq(1)
  end

  it 'does not re-notify after a reaction is removed and the count returns to 2' do
    react(reactor_a)
    react(reactor_b)
    perform

    reactor_a_reaction = NewsCommentReaction.find_by(user: reactor_a, news_comment: comment)
    reactor_a_reaction.destroy!
    react(reactor_c)
    perform

    expect(NewsConversationReminderMailer).to have_received(:comment_agreement_email).once
  end

  it 'enforces at most one notification per user/news_feed/type/comment at the database level' do
    Notification.create!(user: author, news_feed: news_feed, notification_type: 'comment_agreement', news_comment: comment)

    expect do
      Notification.new(user: author, news_feed: news_feed, notification_type: 'comment_agreement', news_comment: comment).save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not interfere with a different comment on the same news_feed (separate dedup per comment)' do
    other_comment = NewsComment.create!(
      text: 'otro comentario',
      user: author,
      news_feed: news_feed,
      user_info: { 'email' => 'author@example.com', 'complete_name' => 'Autor Test' },
    )

    react(reactor_a)
    react(reactor_b)
    perform

    NewsCommentReaction.create!(user: reactor_a, news_comment: other_comment)
    NewsCommentReaction.create!(user: reactor_b, news_comment: other_comment)
    described_class.new.perform(other_comment.id)

    expect(NewsConversationReminderMailer).to have_received(:comment_agreement_email).twice
    expect(Notification.where(user: author, news_feed: news_feed, notification_type: 'comment_agreement').count).to eq(2)
  end

  it 'does not interfere with first_comment_reply/news_conversation_reminder notifications for the same news_feed' do
    allow(NewsConversationReminderMailer).to receive(:first_reply_email).and_return(double(deliver_later: true))

    other_commenter = create_user('other_commenter@example.com')
    NewsComment.create!(
      text: 'segundo comentario',
      user: other_commenter,
      news_feed: news_feed,
      user_info: { 'email' => 'other_commenter@example.com', 'complete_name' => 'Otro' },
    )
    FirstCommentReplyWorker.new.perform(news_feed.id)

    react(reactor_a)
    react(reactor_b)
    perform

    expect(
      Notification.where(user: author, news_feed: news_feed, notification_type: 'first_comment_reply').count
    ).to eq(1)
    expect(
      Notification.where(user: author, news_feed: news_feed, notification_type: 'comment_agreement').count
    ).to eq(1)
  end
end
