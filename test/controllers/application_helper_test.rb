require "test_helper"

class RailsAnalytics::ApplicationHelperTest < ActionView::TestCase
  test "tracker tag uses engine route helper for src and mount for endpoint" do
    html = rails_analytics_tracker_tag
    assert_includes html, 'src="/rails_analytics/tracker.js"'
    assert_includes html, 'data-endpoint="/rails_analytics"'
  end

  test "tracker tag allows explicit endpoint override" do
    html = rails_analytics_tracker_tag endpoint: "/cdn/analytics", tracker: "/cdn/analytics/tracker.js"
    assert_includes html, 'data-endpoint="/cdn/analytics"'
  end
end
