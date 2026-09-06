# frozen_string_literal: true

module RailsAnalytics
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Instala o rails_analytics: copia migração, monta o engine e injeta o tracker no layout."

      def copy_migration
        copy_file "create_rails_analytics_page_views.rb",
                  "db/migrate/#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_create_rails_analytics_page_views.rb"
      end

      def mount_engine
        route 'mount RailsAnalytics::Engine => "/rails_analytics"'
      end

      def inject_tracker
        return unless (layout = Dir["app/views/layouts/*.html.erb"].first)

        if File.read(layout).include?("rails_analytics_tracker_tag")
          say_status :skipped, "tracker já injetado em #{layout}", :yellow
          return
        end

        inject_into_file layout, before: "</head>" do
          "\n    <%= rails_analytics_tracker_tag %>\n"
        end
        say_status :injected, "tracker adicionado ao <head> de #{layout}", :green
      end
    end
  end
end