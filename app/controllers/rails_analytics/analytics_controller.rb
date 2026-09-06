# frozen_string_literal: true

module RailsAnalytics
  class AnalyticsController < ApplicationController
    # O pixel é chamado cross-origin friendly (mesmo-origin por padrão), sem session/cookie
    skip_before_action :verify_authenticity_token

    # GIF transparente 1x1
    TRANSPARENT_1PX_GIF = Base64.decode64(
      "R0lGODlhAQABAPAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=="
    ).freeze

    def px
      PageView.create!(
        path:         params[:path].to_s[0, 500],
        referrer:     params[:referrer].to_s[0, 500].presence,
        title:        params[:title].to_s[0, 255].presence,
        screen_width: params[:sw].to_i,
        screen_height: params[:sh].to_i,
        language:     params[:lang].to_s[0, 8].presence,
        user_agent:   request.user_agent.to_s[0, 255].presence,
        ip_hash:      PageView.ip_hash_from(request.remote_ip),
        session_id:   params[:sid].to_s[0, 64].presence,
        viewed_at:    Time.current
      )
      render plain: TRANSPARENT_1PX_GIF, content_type: "image/gif"
    rescue ActiveRecord::RecordInvalid
      head :bad_request
    end

    def tracker
      render plain: TrackerScript.source, content_type: "application/javascript", layout: false
    end

    def dashboard_css
      css = File.read(RailsAnalytics::Engine.root.join("app/assets/stylesheets/rails_analytics/dashboard.css"))
      render plain: css, content_type: "text/css", layout: false
    end
  end
end