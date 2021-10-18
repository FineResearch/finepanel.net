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

ActiveRecord::Schema.define(version: 2021_10_06_142940) do

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
    t.index ["article_id"], name: "index_news_feeds_on_article_id"
    t.index ["specialty_id"], name: "index_news_feeds_on_specialty_id"
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
    t.index ["encrypted_email"], name: "index_users_on_encrypted_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["spanel"], name: "index_users_on_spanel"
  end

  add_foreign_key "articles", "specialties"
  add_foreign_key "news_comments", "news_feeds"
  add_foreign_key "news_comments", "users"
  add_foreign_key "news_feeds", "articles"
  add_foreign_key "news_feeds", "specialties"
end
