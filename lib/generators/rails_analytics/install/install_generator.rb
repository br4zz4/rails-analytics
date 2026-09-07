# frozen_string_literal: true

module RailsAnalytics
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Instala o rails_analytics: copia migrations, monta engine, cria initializer e pina tracker no importmap."

      # The only mount configuration that matters is the `mount` line this generator
      # writes into config/routes.rb. Changing that line is enough — the tracker and
      # dashboard derive their URLs from the engine's route helpers at runtime.
      DEFAULT_MOUNT_PATH = "/analytics"

      def copy_migrations
        migrations_dir = RailsAnalytics::Engine.root.join("db/migrate")
        Dir["#{migrations_dir}/*.rb"].sort.each do |migration|
          filename = File.basename(migration)
          copy_file migration, "db/migrate/#{filename}"
        end
        say_status :ok, "Migrations copiadas para db/migrate/"
      end

      def create_initializer
        template "initializer.rb", "config/initializers/rails_analytics.rb"
        say_status :ok, "Initializer criado em config/initializers/rails_analytics.rb"
      end

      def mount_engine
        route %(mount RailsAnalytics::Engine => "#{DEFAULT_MOUNT_PATH}")
        say_status :ok, "Engine montada em config/routes.rb (montada em #{DEFAULT_MOUNT_PATH})"
      end

      def pin_tracker
        importmap_path = "config/importmap.rb"
        if File.exist?(importmap_path)
          unless File.read(importmap_path).include?("rails_analytics/tracker")
            append_to_file importmap_path, %(\npin "rails_analytics/tracker", to: "#{DEFAULT_MOUNT_PATH}/tracker.js"\n)
            say_status :ok, "Tracker pinado em config/importmap.rb"
          end
        else
          say_status :skipped, "config/importmap.rb não encontrado — adicione manualmente:", :yellow
          say %(  Adicione ao seu layout: <script src="#{DEFAULT_MOUNT_PATH}/tracker.js" defer></script>), :yellow
        end
      end

      def instructions
        say "\n✅ rails_analytics instalado! Próximos passos:", :green
        say "  1. bin/rails db:migrate"
        say "  2. Configure a autenticação no initializer: config/initializers/rails_analytics.rb"
        say "  3. Acesse o dashboard em #{DEFAULT_MOUNT_PATH} (se quiser outro path, edite o mount em config/routes.rb)"
        say ""
      end
    end
  end
end