# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_06_203100) do
  create_table "rails_analytics_daily_salts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "salt", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_rails_analytics_daily_salts_on_date", unique: true
  end

  create_table "rails_analytics_page_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_hash"
    t.string "language"
    t.string "path", null: false
    t.string "referrer"
    t.integer "screen_height"
    t.integer "screen_width"
    t.string "session_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.datetime "viewed_at", null: false
    t.index ["path"], name: "index_rails_analytics_page_views_on_path"
    t.index ["session_id"], name: "index_rails_analytics_page_views_on_session_id"
    t.index ["viewed_at"], name: "index_rails_analytics_page_views_on_viewed_at"
  end

  create_table "rails_analytics_visits", force: :cascade do |t|
    t.string "anonymity_key", null: false
    t.string "country"
    t.datetime "created_at", null: false
    t.string "device_type"
    t.text "landing_page_path"
    t.string "language"
    t.string "masked_ip", null: false
    t.string "referrer_domain"
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "viewport"
    t.index ["anonymity_key", "started_at"], name: "idx_visits_anonymity_started"
    t.index ["started_at"], name: "index_rails_analytics_visits_on_started_at"
  end
end
