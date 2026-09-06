# frozen_string_literal: true

RailsAnalytics.configure do |config|
  # Método de autenticação para o dashboard.
  # Pode ser um Symbol (ex: :authenticate_admin!) ou um callable (ex: -> { current_user&.admin? }).
  config.auth_callback = :authenticate_admin!

  # Caminho onde o engine será montado no routes.rb.
  config.mount_path = "/analytics"

  # Período padrão para as consultas do dashboard (ex: 30.days).
  config.since_default = 30.days
end