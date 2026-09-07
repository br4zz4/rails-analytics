# frozen_string_literal: true

# Seeds de demonstração: popular o dashboard da engine rails_analytics
# com dados anônimos realistas (visits + events ao longo de ~30 dias).
# Uso: bin/rails db:seed

require "securerandom"

RailsAnalytics::Event.delete_all
RailsAnalytics::Visit.delete_all

SOURCES = ["google.com", "instagram.com", "facebook.com", "whatsapp.com", "tiktok.com", "twitter.com", "direct"].freeze
CAMPAIGNS = ["lancamento", "janeiro", "fevereiro", "doacao", "voluntariado"].freeze
DEVICES = ["desktop", "mobile", "tablet"].freeze
LANGS = ["pt-BR", "pt", "en", "es"].freeze
PATHS = ["/", "/", "/", "/propostas", "/eventos", "/doacao", "/contato"].freeze

EVENTS = {
  "doacao-click" => 50,
  "participe-click" => 30,
  "instagram-click" => 25,
  "email-click" => 15,
  "whatsapp-click" => 10,
  "scroll-depth" => 80,
  "form-start:participe" => 20,
  "form-submit:participe" => 8
}.freeze
EVENT_NAMES = EVENTS.keys.freeze

rng = Random.new(2026)

puts "Seeding rails_analytics demo data..."

# 30 dias: 40 a 90 visits/dia
(30.downto(1)).each do |day|
  daily = rng.rand(40..90)
  daily.times do
    started = rng.rand(0..29).days.ago.change(hour: rng.rand(7..23), min: rng.rand(0..59))

    source = SOURCES.sample(random: rng)
    device = DEVICES.sample(random: rng)
    path = PATHS.sample(random: rng)
    campaign = source == "direct" ? nil : CAMPAIGNS.sample(random: rng)

    visit = RailsAnalytics::Visit.create!(
      anonymity_key:      SecureRandom.hex(16),
      masked_ip:          "#{rng.rand(1..223)}.#{rng.rand(0..255)}.#{rng.rand(0..255)}.0",
      referrer_domain:    source,
      landing_page_path:  path,
      device_type:        device,
      viewport:           device == "mobile" ? "390x844" : (device == "tablet" ? "768x1024" : "1440x900"),
      language:           LANGS.sample(random: rng),
      utm_source:         (source == "direct" ? nil : source.gsub(".com", "")),
      utm_campaign:       campaign,
      started_at:         started
    )

    # Bounce: ~50% das visits não interagem (sem eventos)
    next if rng.rand < 0.5

    # 1 a 3 eventos por visit interativa
    rng.rand(1..3).times do
      name = EVENT_NAMES.sample(random: rng)
      visit.events.create!(
        name: name,
        time: started + rng.rand(0..30).minutes,
        properties: name == "scroll-depth" ? { "mark" => [25, 50, 75, 100].sample(random: rng) } : {}
      )
    end
  end
end

puts "Seeded: #{RailsAnalytics::Visit.count} visits, #{RailsAnalytics::Event.count} events"