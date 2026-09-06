# frozen_string_literal: true

module RailsAnalytics
  class AnalyticsController < ApplicationController
    skip_before_action :authorize_admin!
    skip_before_action :verify_authenticity_token

    TOKEN_PURPOSE = :tracker
    VERIFIER_NAME = "rails_analytics_tracker"

    def collect
      json = JSON.parse(request.body.read)
      token = extract_token(request, json)

      unless valid_token?(token)
        render json: { error: "Unauthorized" }, status: :unauthorized and return
      end

      client_ip = request.env["HTTP_CF_CONNECTING_IP"] || request.remote_ip
      masked = IpMask.mask(client_ip)
      ua = request.user_agent.to_s
      path = json["path"].to_s[0, 2000]

      anonymity_key = Identity.key(
        masked_ip: masked,
        user_agent: ua,
        date: Date.today
      )

      utm = Visit.parse_utm_params(path)

      visit = Visit.find_or_create_for(anonymity_key, {
        masked_ip: masked,
        referrer_domain: json["referrer_domain"].to_s[0, 500].presence,
        landing_page_path: path,
        device_type: json["device_type"].to_s[0, 50].presence || "unknown",
        viewport: json["viewport"].to_s[0, 20].presence,
        language: json["language"].to_s[0, 10].presence,
        started_at: Time.current,
        **utm
      })

      Array(json["events"]).each do |ev|
        next unless ev.is_a?(Hash)
        visit.events.create!(
          name: ev["name"].to_s[0, 100],
          time: (Time.parse(ev["time"].to_s) rescue Time.current),
          properties: (ev["properties"].is_a?(Hash) ? ev["properties"] : {})
        )
      end

      head :no_content
    rescue JSON::ParserError, ActiveRecord::RecordInvalid, ArgumentError
      head :no_content
    end

    def token
      verifier = Rails.application.message_verifier(VERIFIER_NAME)
      signed = verifier.generate({ exp: 5.minutes.from_now.to_i, nonce: SecureRandom.hex(8) }, purpose: TOKEN_PURPOSE)
      render json: { token: signed }
    end

    def tracker
      js = File.read(RailsAnalytics::Engine.root.join("app/assets/javascripts/rails_analytics/tracker.js"))
      render plain: js, content_type: "application/javascript", layout: false
    end

    def dashboard_css
      css = File.read(RailsAnalytics::Engine.root.join("app/assets/stylesheets/rails_analytics/dashboard.css"))
      render plain: css, content_type: "text/css", layout: false
    end

    private

    # sendBeacon does not allow custom headers — accept token in header OR body.
    def extract_token(request, json)
      header = request.headers["Authorization"]
      return header.gsub(/^Bearer /, "") if header.present?
      json["token"]
    end

    def valid_token?(token)
      return false if token.blank?
      verifier = Rails.application.message_verifier(VERIFIER_NAME)
      payload = verifier.verified(token, purpose: TOKEN_PURPOSE)
      payload.present? && payload["exp"].to_i > Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end
  end
end