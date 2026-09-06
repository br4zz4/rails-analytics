class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  def index
    render plain: "dummy"
  end

  private

  def authenticate_admin!
    redirect_to main_app.root_path, alert: "Não autorizado."
  end
end
