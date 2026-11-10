require "test_helper"

class Sportradar::Ncaafb::ClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  def client(**opts)
    Sportradar::Ncaafb::Client.new(api_key: "key", cache: ActiveSupport::Cache::NullStore.new, **opts)
  end

  def stub_http(response)
    captured = []
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |req| captured << req; response }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      yield
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
    captured
  end

  test "builds URL and sends api key header" do
    reqs = stub_http(FakeResponse.new("200", '{"ok":true}')) do
      assert_equal({ "ok" => true }, client.season_schedule(2025, "reg"))
    end
    assert_equal "/ncaafb/trial/v7/en/games/2025/REG/schedule.json", reqs.first.uri.path
    assert_equal "key", reqs.first["x-api-key"]
  end

  test "maps error statuses" do
    stub_http(FakeResponse.new("429", "")) do
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.league_hierarchy }
    end
    stub_http(FakeResponse.new("404", "")) do
      assert_raises(Sportradar::Ncaafb::Client::NotFoundError) { client.league_hierarchy }
    end
    stub_http(FakeResponse.new("500", "")) do
      assert_raises(Sportradar::Ncaafb::Client::Error) { client.league_hierarchy }
    end
  end

  test "requires api key" do
    c = Sportradar::Ncaafb::Client.new(api_key: nil)
    assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { c.league_hierarchy }
  end

  test "rejects bad season type and ids" do
    assert_raises(ArgumentError) { client.season_schedule(2025, "XXX") }
    assert_raises(ArgumentError) { client.game_summary("../x") }
  end
end
