# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  def index
    render :index
  end

  def login
    session[:admin] = true
    redirect_to main_app.root_path, notice: "Logado como admin."
  end

  def logout
    session[:admin] = nil
    redirect_to main_app.root_path, notice: "Deslogado."
  end

  private

  def authenticate_admin!
    return if session[:admin]

    redirect_to main_app.login_path, alert: "Faça login para acessar o dashboard."
  end
end