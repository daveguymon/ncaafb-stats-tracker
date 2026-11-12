require "test_helper"

class Sportradar::Ncaafb::ClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body, :headers) do
    def [](name)
      headers&.[](name)
    end
  end

  class ImmediateCoordinator
    attr_reader :delays

    def initialize
      @delays = []
    end

    def synchronize
      yield self
    end

    def wait!; end

    def reserve!(limit:, window_seconds:, visitor_key:, visitor_limit:, visitor_window_seconds:); end

    def defer!(delay)
      @delays << delay
    end
  end

  def client(**opts)
    Sportradar::Ncaafb::Client.new(api_key: "key", cache: ActiveSupport::Cache::NullStore.new, coordinator: ImmediateCoordinator.new, **opts)
  end

  def stub_http(response)
    captured = []
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
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

  test "maps malformed upstream JSON to a client error without exposing the response" do
    stub_http(FakeResponse.new("200", "not-json-secret")) do
      error = assert_raises(Sportradar::Ncaafb::Client::Error) { client.league_hierarchy }
      assert_equal "Sportradar returned invalid JSON", error.message
    end
  end

  test "requires api key" do
    c = Sportradar::Ncaafb::Client.new(api_key: nil)
    assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { c.league_hierarchy }
  end

  test "validates quota settings and requires a limit in production" do
    [ "0", "-1", "invalid" ].each do |value|
      assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { client(quota_limit: value) }
      assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { client(quota_limit: 10, quota_window_seconds: value) }
    end
    assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { client(quota_limit: nil, quota_window_seconds: 60) }
    original_env = Rails.env
    begin
      Rails.env = "production"
      assert_raises(Sportradar::Ncaafb::Client::ConfigurationError) { client(quota_limit: nil, quota_window_seconds: nil) }
      assert_instance_of Sportradar::Ncaafb::Client, client(quota_limit: 10, quota_window_seconds: nil)
    ensure
      Rails.env = original_env
    end
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
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| responses.shift }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      c = client
      games = c.team_games(2025)
      assert_equal %w[a b], games.map { |g| g["id"] }
      assert_equal [ "REG" ], games.map { |g| g["season_type"] }.uniq
      assert_equal [ "1", "1" ], games.map { |g| g["week"] }
      assert_equal({ path: "games/2025/PST/schedule", source: :not_found, fetched_at: nil }, c.request_metadata.last)
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
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: ImmediateCoordinator.new)
    reqs = stub_http(FakeResponse.new("200", '{"ok":true}')) do
      2.times { assert_equal({ "ok" => true }, c.league_hierarchy) }
    end
    assert_equal 1, reqs.size
  end

  test "instruments cache and HTTP activity without including request identifiers" do
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| FakeResponse.new("200", '{"ok":true}') }
    client = Sportradar::Ncaafb::Client.new(api_key: "test-key", access_level: "production",
      cache: ActiveSupport::Cache::MemoryStore.new, coordinator: ImmediateCoordinator.new,
      http_factory: ->(_, _) { fake })
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\Asportradar\./) do |name, _start, _finish, _id, payload|
      events << [ name, payload ]
    end
    begin
      2.times { client.game_summary("private-game-id") }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    assert_equal [ "sportradar.cache", "sportradar.upstream", "sportradar.cache" ], events.map(&:first)
    assert_equal [ "miss", nil, "hit" ], events.map { |_, payload| payload[:outcome] }
    assert_equal 200, events[1][1][:status]
    refute_includes events.inspect, "private-game-id"
    refute_includes events.inspect, "test-key"
  end

  test "records fetch time and cache source while preserving the original payload" do
    store = ActiveSupport::Cache::MemoryStore.new
    coordinator = ImmediateCoordinator.new
    travel_to Time.utc(2026, 11, 12, 9) do
      c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: coordinator)
      stub_http(FakeResponse.new("200", '{"weeks":[]}')) do
        assert_equal({ "weeks" => [] }, c.season_schedule(2026))
        assert_equal :fetched, c.request_metadata.last[:source]
        assert_equal Time.current, c.request_metadata.last[:fetched_at]
      end
    end
    travel_to Time.utc(2026, 11, 12, 9, 5) do
      c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: ImmediateCoordinator.new)
      assert_equal({ "weeks" => [] }, c.season_schedule(2026))
      assert_equal :cached, c.request_metadata.last[:source]
      assert_equal Time.utc(2026, 11, 12, 9), c.request_metadata.last[:fetched_at]
    end
    travel_to Time.utc(2026, 11, 12, 9, 11) do
      c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: coordinator)
      stub_http(FakeResponse.new("200", '{"weeks":[{"title":"new"}]}')) do
        assert_equal({ "weeks" => [ { "title" => "new" } ] }, c.season_schedule(2026))
        assert_equal :fetched, c.request_metadata.last[:source]
        assert_equal Time.current, c.request_metadata.last[:fetched_at]
      end
    end
  end

  test "reports a legacy cached payload with unknown fetch time" do
    store = ActiveSupport::Cache::MemoryStore.new
    store.write([ "sportradar/ncaafb", "trial", "league/hierarchy" ], { "legacy" => true })
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: ImmediateCoordinator.new)
    assert_equal({ "legacy" => true }, c.league_hierarchy)
    assert_equal({ path: "league/hierarchy", source: :cached, fetched_at: nil }, c.request_metadata.last)
  end

  test "does not reuse a language-less legacy entry for other languages" do
    store = ActiveSupport::Cache::MemoryStore.new
    store.write([ "sportradar/ncaafb", "trial", "league/hierarchy" ], { "legacy" => true })
    c = Sportradar::Ncaafb::Client.new(api_key: "key", language: "es", cache: store, coordinator: ImmediateCoordinator.new)
    reqs = stub_http(FakeResponse.new("200", '{"spanish":true}')) do
      assert_equal({ "spanish" => true }, c.league_hierarchy)
      assert_equal :fetched, c.request_metadata.last[:source]
    end
    assert_equal "/ncaafb/trial/v7/es/league/hierarchy.json", reqs.first.uri.path
  end

  test "does not cache errors" do
    store = ActiveSupport::Cache::MemoryStore.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: ImmediateCoordinator.new)
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

  test "retries a short rate limit once and caches the successful response" do
    responses = [ FakeResponse.new("429", "", { "Retry-After" => "0" }), FakeResponse.new("200", '{"ok":true}') ]
    coordinator = ImmediateCoordinator.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: ActiveSupport::Cache::MemoryStore.new, coordinator: coordinator)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| responses.shift }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_equal({ "ok" => true }, c.league_hierarchy)
      assert_equal({ "ok" => true }, c.league_hierarchy)
      assert_empty responses
      assert_equal [ 1, 1, 1 ], coordinator.delays
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "does not retry a long rate limit and retains the cooldown" do
    coordinator = ImmediateCoordinator.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator)
    reqs = stub_http(FakeResponse.new("429", "", { "Retry-After" => "120" })) do
      error = assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { c.league_hierarchy }
      assert_equal 429, error.status
    end
    assert_equal 1, reqs.size
    assert_equal [ 1, 120 ], coordinator.delays
  end

  test "bounds retries and does not cache rate limit responses" do
    coordinator = ImmediateCoordinator.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: ActiveSupport::Cache::MemoryStore.new, coordinator: coordinator)
    reqs = stub_http(FakeResponse.new("429", "")) do
      2.times { assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { c.league_hierarchy } }
    end
    assert_equal 4, reqs.size
  end

  test "parses Retry-After HTTP dates and handles malformed values" do
    c = client
    travel_to Time.utc(2026, 11, 12, 12) do
      assert_equal 2, c.send(:retry_after, 2.seconds.from_now.httpdate)
      assert_equal 0, c.send(:retry_after, 1.second.ago.httpdate)
      assert_equal 1, c.send(:retry_after, "invalid")
    end
  end

  test "reports a busy coordinator as a rate limit and still serves cache hits" do
    coordinator = Object.new
    coordinator.define_singleton_method(:synchronize) { raise Sportradar::Ncaafb::RequestCoordinator::Busy, "busy" }
    store = ActiveSupport::Cache::MemoryStore.new
    c = Sportradar::Ncaafb::Client.new(api_key: "key", cache: store, coordinator: coordinator)
    assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { c.league_hierarchy }

    store.write([ "sportradar/ncaafb", "trial", "league/hierarchy" ], { "cached" => true })
    assert_equal({ "cached" => true }, c.league_hierarchy)
  end
end
