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
end
