# frozen_string_literal: true

class CreateRailsAnalyticsEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_analytics_events do |t|
      t.references :visit, null: false, foreign_key: { to_table: :rails_analytics_visits }
      t.string     :name, null: false
      if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
        t.jsonb :properties, default: {}
      else
        t.json :properties, default: {}
      end
      t.datetime   :time, null: false

      t.timestamps
    end

    add_index :rails_analytics_events, :name
    add_index :rails_analytics_events, :time
    add_index :rails_analytics_events, [:name, :time]
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      add_index :rails_analytics_events, :properties, using: :gin
    end
  end
end