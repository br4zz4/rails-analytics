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

ActiveRecord::Schema[8.1].define(version: 2026_09_06_202926) do
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
end
