require "test_helper"

class SportradarControllerTest < ActionDispatch::IntegrationTest
  test "returns 503 when api key missing" do
    original = ENV["SPORTRADAR_API_KEY"]
    ENV.delete("SPORTRADAR_API_KEY")
    get "/sportradar/hierarchy"
    assert_response :service_unavailable
  ensure
    ENV["SPORTRADAR_API_KEY"] = original if original
  end

  test "returns a clear 429 when the upstream request limit is reached" do
    client = Object.new
    client.define_singleton_method(:league_hierarchy) do
      raise Sportradar::Ncaafb::Client::RateLimitError, "Rate limited"
    end
    original = Sportradar::Ncaafb::Client.method(:new)
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { |**| client }
    get "/sportradar/hierarchy"
    assert_response :too_many_requests
    assert_match(/check your account quota/, response.parsed_body.fetch("error"))
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end

  test "returns 503 for invalid quota configuration" do
    original = ENV["SPORTRADAR_QUOTA_LIMIT"]
    ENV["SPORTRADAR_QUOTA_LIMIT"] = "0"
    get "/sportradar/hierarchy"
    assert_response :service_unavailable
    assert_match(/not configured/, response.parsed_body.fetch("error"))
  ensure
    ENV["SPORTRADAR_QUOTA_LIMIT"] = original
  end

  test "returns a controlled upstream error for invalid provider data" do
    client = Object.new
    client.define_singleton_method(:league_hierarchy) do
      raise Sportradar::Ncaafb::Client::Error, "Sportradar returned invalid JSON"
    end
    original = Sportradar::Ncaafb::Client.method(:new)
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { |**| client }
    get "/sportradar/hierarchy"
    assert_response :bad_gateway
    assert_equal "Upstream Sportradar error", response.parsed_body.fetch("error")
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end

  test "distinguishes visitor throttling from the provider quota" do
    client = Object.new
    client.define_singleton_method(:league_hierarchy) do
      raise Sportradar::Ncaafb::Client::VisitorRateLimitError, "Limited"
    end
    original = Sportradar::Ncaafb::Client.method(:new)
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { |**| client }
    get "/sportradar/hierarchy"
    assert_response :too_many_requests
    assert_match(/Too many new data requests/, response.parsed_body.fetch("error"))
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end
end
