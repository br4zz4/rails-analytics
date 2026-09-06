# frozen_string_literal: true

class CreateRailsAnalyticsPageViews < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_page_views do |t|
      t.string :path, null: false
      t.string :referrer
      t.string :title
      t.integer :screen_width
      t.integer :screen_height
      t.string :language
      t.string :user_agent
      t.string :ip_hash
      t.string :session_id
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :rails_analytics_page_views, :viewed_at
    add_index :rails_analytics_page_views, :path
    add_index :rails_analytics_page_views, :session_id
  end
end