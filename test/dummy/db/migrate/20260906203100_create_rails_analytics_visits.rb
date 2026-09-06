# frozen_string_literal: true

class CreateRailsAnalyticsVisits < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_visits do |t|
      t.string   :anonymity_key,  null: false
      t.string   :masked_ip,      null: false
      t.string   :referrer_domain
      t.text     :landing_page_path
      t.string   :device_type
      t.string   :viewport
      t.string   :language
      t.string   :country
      t.string   :utm_source
      t.string   :utm_medium
      t.string   :utm_campaign
      t.string   :utm_term
      t.string   :utm_content
      t.datetime :started_at,     null: false

      t.timestamps
    end

    add_index :rails_analytics_visits, :started_at
    add_index :rails_analytics_visits, [:anonymity_key, :started_at], name: "idx_visits_anonymity_started"
  end
end