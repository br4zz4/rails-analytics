# frozen_string_literal: true

class CreateRailsAnalyticsDailySalts < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_daily_salts do |t|
      t.date :date, null: false
      t.string :salt, null: false

      t.timestamps
    end

    add_index :rails_analytics_daily_salts, :date, unique: true
  end
end