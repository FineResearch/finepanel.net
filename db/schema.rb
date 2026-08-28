# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_08_27_120000) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "articles", force: :cascade do |t|
    t.string "dynamed_id"
    t.string "title"
    t.string "slug"
    t.bigint "specialty_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dynamed_id"], name: "index_articles_on_dynamed_id"
    t.index ["specialty_id"], name: "index_articles_on_specialty_id"
  end

  create_table "comments", force: :cascade do |t|
    t.string "text"
    t.bigint "user_id"
    t.bigint "post_id"
    t.jsonb "user_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_comments_on_post_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "internal_user_project_accesses", force: :cascade do |t|
    t.bigint "internal_user_id", null: false
    t.string "project_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["internal_user_id", "project_code"], name: "idx_internal_user_project_access_unique", unique: true
    t.index ["internal_user_id"], name: "index_internal_user_project_accesses_on_internal_user_id"
    t.index ["project_code"], name: "index_internal_user_project_accesses_on_project_code"
  end

  create_table "internal_users", force: :cascade do |t|
    t.string "email", null: false
    t.string "role", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.index ["active"], name: "index_internal_users_on_active"
    t.index ["email"], name: "index_internal_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_internal_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_internal_users_on_role"
  end

  create_table "invalid_whatsapp_numbers", force: :cascade do |t|
    t.integer "panelist_id"
    t.string "panelist_email"
    t.string "whatsapp_number"
    t.string "first_detected_project_code"
    t.string "last_detected_project_code"
    t.datetime "first_detected_at"
    t.datetime "last_detected_at"
    t.integer "times_detected", default: 1
    t.text "last_error_message"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["panelist_id"], name: "index_invalid_whatsapp_numbers_on_panelist_id"
    t.index ["whatsapp_number"], name: "index_invalid_whatsapp_numbers_on_whatsapp_number"
  end

  create_table "news_comments", force: :cascade do |t|
    t.string "text"
    t.bigint "user_id"
    t.bigint "news_feed_id"
    t.jsonb "user_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_feed_id"], name: "index_news_comments_on_news_feed_id"
    t.index ["user_id"], name: "index_news_comments_on_user_id"
  end

  create_table "news_feed_reactions", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "news_feed_id"
    t.boolean "useful", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_feed_id"], name: "index_news_feed_reactions_on_news_feed_id"
    t.index ["user_id", "news_feed_id"], name: "index_news_feed_reactions_on_user_and_news_feed", unique: true
    t.index ["user_id"], name: "index_news_feed_reactions_on_user_id"
  end

  create_table "news_feed_translations", force: :cascade do |t|
    t.bigint "news_feed_id"
    t.integer "locale"
    t.string "title"
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_feed_id"], name: "index_news_feed_translations_on_news_feed_id"
  end

  create_table "news_feeds", force: :cascade do |t|
    t.text "text"
    t.string "link"
    t.string "anchor"
    t.datetime "alert_created_at"
    t.string "update_type"
    t.string "update_priority"
    t.bigint "specialty_id"
    t.bigint "article_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0, null: false
    t.string "title"
    t.jsonb "fine_news_summary"
    t.jsonb "fine_news_summary_translations"
    t.index ["article_id"], name: "index_news_feeds_on_article_id"
    t.index ["specialty_id"], name: "index_news_feeds_on_specialty_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "news_feed_id"
    t.string "notification_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["news_feed_id"], name: "index_notifications_on_news_feed_id"
    t.index ["user_id", "news_feed_id", "notification_type"], name: "index_notifications_on_user_news_feed_and_type", unique: true
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.string "respid", default: "", null: false
    t.string "project_name"
    t.integer "credit", default: 0, null: false
    t.string "concept"
    t.date "email_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["respid", "project_name", "credit", "concept", "email_date"], name: "index_payment_on_respid_project_credit_concept_email"
    t.index ["respid", "project_name", "credit", "concept", "email_date"], name: "unique_payments", unique: true
    t.index ["respid"], name: "index_payments_on_respid"
  end

  create_table "posts", force: :cascade do |t|
    t.string "text"
    t.bigint "user_id"
    t.string "media"
    t.string "external_media_url"
    t.string "kind"
    t.jsonb "user_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "specialties", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "survey_links", force: :cascade do |t|
    t.string "project_id", default: "", null: false
    t.string "resp_id", default: "", null: false
    t.string "spanel", default: "", null: false
    t.string "link", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "variables"
    t.boolean "closed", default: false
    t.index ["project_id", "resp_id", "spanel", "link", "variables"], name: "unique_survey_links", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "encrypted_email", default: "", null: false
    t.string "hash_respid", default: "", null: false
    t.string "spanel", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "remember_token"
    t.boolean "active_app"
    t.integer "language"
    t.string "jti", null: false
    t.string "country"
    t.string "whatsapp_number"
    t.string "first_name"
    t.string "last_name"
    t.string "professional_title"
    t.string "formal_title"
    t.boolean "whatsapp_opt_in", default: false, null: false
    t.datetime "whatsapp_opt_in_at"
    t.string "whatsapp_opt_in_source"
    t.index ["encrypted_email"], name: "index_users_on_encrypted_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["spanel"], name: "index_users_on_spanel"
  end

  create_table "whatsapp_conversations", force: :cascade do |t|
    t.bigint "user_id"
    t.string "panelist_id", null: false
    t.string "panelist_email"
    t.string "whatsapp_number"
    t.string "project_code", null: false
    t.string "sample_number"
    t.string "support_email"
    t.string "country"
    t.string "status", default: "open", null: false
    t.datetime "last_inbound_at"
    t.datetime "last_outbound_at"
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "has_unread_messages", default: false, null: false
    t.datetime "window_expires_at"
    t.datetime "resolved_at"
    t.bigint "resolved_by_user_id"
    t.string "panelist_country"
    t.index ["has_unread_messages"], name: "index_whatsapp_conversations_on_has_unread_messages"
    t.index ["panelist_id", "project_code"], name: "idx_whatsapp_conversations_panelist_project", unique: true
    t.index ["project_code"], name: "index_whatsapp_conversations_on_project_code"
    t.index ["resolved_at"], name: "index_whatsapp_conversations_on_resolved_at"
    t.index ["resolved_by_user_id"], name: "index_whatsapp_conversations_on_resolved_by_user_id"
    t.index ["status"], name: "index_whatsapp_conversations_on_status"
    t.index ["user_id"], name: "index_whatsapp_conversations_on_user_id"
    t.index ["whatsapp_number"], name: "index_whatsapp_conversations_on_whatsapp_number"
    t.index ["window_expires_at"], name: "index_whatsapp_conversations_on_window_expires_at"
  end

  create_table "whatsapp_delivery_results", force: :cascade do |t|
    t.string "project_code"
    t.string "sample_number"
    t.integer "panelist_id"
    t.string "panelist_email"
    t.string "whatsapp_number"
    t.string "status"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["panelist_id"], name: "index_whatsapp_delivery_results_on_panelist_id"
    t.index ["project_code"], name: "index_whatsapp_delivery_results_on_project_code"
    t.index ["sample_number"], name: "index_whatsapp_delivery_results_on_sample_number"
    t.index ["status"], name: "index_whatsapp_delivery_results_on_status"
  end

  create_table "whatsapp_messages", force: :cascade do |t|
    t.bigint "whatsapp_conversation_id", null: false
    t.string "direction", null: false
    t.string "message_type"
    t.text "message_body"
    t.string "message_id"
    t.string "status"
    t.string "from_phone_number"
    t.string "from_phone_number_id"
    t.string "to_phone_number"
    t.string "template_name"
    t.string "language"
    t.text "payload_json"
    t.datetime "sent_at"
    t.datetime "received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "webhook", null: false
    t.bigint "internal_user_id"
    t.string "template_language"
    t.index ["direction"], name: "index_whatsapp_messages_on_direction"
    t.index ["internal_user_id"], name: "index_whatsapp_messages_on_internal_user_id"
    t.index ["message_id"], name: "index_whatsapp_messages_on_message_id"
    t.index ["received_at"], name: "index_whatsapp_messages_on_received_at"
    t.index ["sent_at"], name: "index_whatsapp_messages_on_sent_at"
    t.index ["source"], name: "index_whatsapp_messages_on_source"
    t.index ["status"], name: "index_whatsapp_messages_on_status"
    t.index ["whatsapp_conversation_id"], name: "index_whatsapp_messages_on_whatsapp_conversation_id"
  end

  create_table "whatsapp_outbounds", force: :cascade do |t|
    t.bigint "user_id"
    t.string "whatsapp_number"
    t.string "panelist_email"
    t.string "subject"
    t.string "project_code"
    t.string "duration"
    t.string "incentive"
    t.string "sent_by"
    t.text "survey_link"
    t.text "main_survey_link"
    t.string "template_name"
    t.string "language"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "panelist_id"
    t.string "sample_number"
    t.string "support_email"
    t.string "from_phone_number"
    t.string "from_phone_number_id"
    t.text "error_message"
    t.string "campaign_uuid"
    t.boolean "include_respondent_phone", default: false, null: false
    t.index ["created_at"], name: "index_whatsapp_outbounds_on_created_at"
    t.index ["project_code"], name: "index_whatsapp_outbounds_on_project_code"
    t.index ["user_id"], name: "index_whatsapp_outbounds_on_user_id"
    t.index ["whatsapp_number"], name: "index_whatsapp_outbounds_on_whatsapp_number"
  end

  create_table "whatsapp_project_panelists", force: :cascade do |t|
    t.bigint "user_id"
    t.string "project_code", null: false
    t.string "panelist_id", null: false
    t.string "panelist_email"
    t.string "sample_number"
    t.string "whatsapp_number"
    t.string "country"
    t.string "support_email"
    t.string "status", default: "not_sent", null: false
    t.boolean "agent_intervened", default: false, null: false
    t.string "confirmit_status"
    t.text "original_survey_link"
    t.text "original_cancel_link"
    t.text "tracked_survey_link"
    t.text "tracked_cancel_link"
    t.datetime "message_sent_at"
    t.datetime "clicked_at"
    t.datetime "cancelled_at"
    t.datetime "reply_received_at"
    t.datetime "final_outcome_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "survey_path"
    t.string "survey_r"
    t.string "survey_s"
    t.string "cancel_path"
    t.string "cancel_r"
    t.string "cancel_s"
    t.index ["cancel_path", "cancel_r", "cancel_s"], name: "idx_whatsapp_project_panelists_cancel_lookup"
    t.index ["panelist_id"], name: "index_whatsapp_project_panelists_on_panelist_id"
    t.index ["project_code", "panelist_id"], name: "idx_whatsapp_project_panelists_unique", unique: true
    t.index ["project_code"], name: "index_whatsapp_project_panelists_on_project_code"
    t.index ["sample_number"], name: "index_whatsapp_project_panelists_on_sample_number"
    t.index ["status"], name: "index_whatsapp_project_panelists_on_status"
    t.index ["survey_path", "survey_r", "survey_s"], name: "idx_whatsapp_project_panelists_survey_lookup"
    t.index ["user_id"], name: "index_whatsapp_project_panelists_on_user_id"
    t.index ["whatsapp_number"], name: "index_whatsapp_project_panelists_on_whatsapp_number"
  end

  add_foreign_key "articles", "specialties"
  add_foreign_key "internal_user_project_accesses", "internal_users"
  add_foreign_key "news_comments", "news_feeds"
  add_foreign_key "news_comments", "users"
  add_foreign_key "news_feed_reactions", "news_feeds"
  add_foreign_key "news_feed_reactions", "users"
  add_foreign_key "news_feed_translations", "news_feeds"
  add_foreign_key "news_feeds", "articles"
  add_foreign_key "news_feeds", "specialties"
  add_foreign_key "notifications", "news_feeds"
  add_foreign_key "notifications", "users"
  add_foreign_key "whatsapp_conversations", "internal_users", column: "resolved_by_user_id"
  add_foreign_key "whatsapp_conversations", "users"
  add_foreign_key "whatsapp_messages", "internal_users"
  add_foreign_key "whatsapp_messages", "whatsapp_conversations"
  add_foreign_key "whatsapp_outbounds", "users"
  add_foreign_key "whatsapp_project_panelists", "users"
end
