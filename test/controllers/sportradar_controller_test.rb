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
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { client }
    get "/sportradar/hierarchy"
    assert_response :too_many_requests
    assert_match(/check your account quota/, response.parsed_body.fetch("error"))
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end
end
