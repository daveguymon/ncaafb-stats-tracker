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

  test "team_games filters the season schedule to the team and tolerates missing postseason" do
    utah = Sportradar::Ncaafb::Teams::UTAH[:id]
    body = { weeks: [ { sequence: 1, title: "1", games: [
      { id: "a", home: { id: utah }, away: { id: "x" } },
      { id: "b", home: { id: "y" }, away: { id: utah } },
      { id: "c", home: { id: "y" }, away: { id: "x" } }
    ] } ] }.to_json
    responses = [ FakeResponse.new("200", body), FakeResponse.new("404", "") ]
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:request) { |_| responses.shift }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      games = client.team_games(2025)
      assert_equal %w[a b], games.map { |g| g["id"] }
      assert_equal [ "REG" ], games.map { |g| g["season_type"] }.uniq
      assert_equal [ "1", "1" ], games.map { |g| g["week"] }
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "team_games propagates a missing regular season" do
    stub_http(FakeResponse.new("404", "")) do
      assert_raises(Sportradar::Ncaafb::Client::NotFoundError) { client.team_games(2025) }
    end
  end

  test "serves repeated requests from cache" do
    store = ActiveSupport::Cache::MemoryStore.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store)
    reqs = stub_http(FakeResponse.new("200", '{"ok":true}')) do
      2.times { assert_equal({ "ok" => true }, c.league_hierarchy) }
    end
    assert_equal 1, reqs.size
  end

  test "does not cache errors" do
    store = ActiveSupport::Cache::MemoryStore.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store)
    reqs = stub_http(FakeResponse.new("500", "")) do
      2.times { assert_raises(Sportradar::Ncaafb::Client::Error) { c.league_hierarchy } }
    end
    assert_equal 2, reqs.size
  end

  test "uses long ttl for closed games and past seasons, short otherwise" do
    c = client
    assert_equal Sportradar::Ncaafb::Client::TTL_FINAL, c.send(:game_ttl, { "status" => "closed" })
    assert_equal Sportradar::Ncaafb::Client::TTL_LIVE, c.send(:game_ttl, { "status" => "inprogress" })
    assert_equal Sportradar::Ncaafb::Client::TTL_FINAL, c.send(:schedule_ttl, 2000)
    assert_equal Sportradar::Ncaafb::Client::TTL_CURRENT_SCHEDULE, c.send(:schedule_ttl, Time.current.year)
  end

  test "play-by-play and statistics hit the right feeds" do
    reqs = stub_http(FakeResponse.new("200", '{"status":"closed"}')) do
      client.game_play_by_play("abc-123")
      client.game_statistics("abc-123")
    end
    assert_equal %w[/ncaafb/trial/v7/en/games/abc-123/pbp.json /ncaafb/trial/v7/en/games/abc-123/statistics.json],
                 reqs.map { |r| r.uri.path }
  end
end
