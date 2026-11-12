require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  def with_client(client)
    original = Sportradar::Ncaafb::Client.method(:new)
    client.define_singleton_method(:request_metadata) { [] } unless client.respond_to?(:request_metadata)
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { client }
    yield
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end

  test "shows the cached play-by-play fetch time and reload semantics" do
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |_| { "periods" => [] } }
    client.define_singleton_method(:request_metadata) do
      [ { path: "games/game-id/pbp", source: :cached, fetched_at: Time.utc(2026, 11, 12, 9, 0) } ]
    end
    with_client(client) { get game_path("game-id") }
    assert_select ".freshness", text: /Play-by-play: Cached; fetched Nov 12, 2026 at 09:00:00 UTC/
    assert_select ".freshness", text: /does not force an upstream refresh/
    assert_select "a", text: /Reload game/
  end

  test "renders plays and standalone events in feed order with scores and statistics" do
    game = {
      "status" => "closed",
      "summary" => {
        "home" => { "id" => "utah", "market" => "Utah", "name" => "Utes", "points" => 21 },
        "away" => { "id" => "idaho", "market" => "Idaho", "name" => "Vandals", "points" => 7 }
      },
      "periods" => [
        { "period_type" => "quarter", "number" => 1, "pbp" => [
          { "type" => "drive", "offensive_team" => { "id" => "utah" },
            "play_count" => 2, "net_yards" => 10, "events" => [
              { "type" => "play", "clock" => "15:00", "description" => "First play",
                "play_type" => "rush", "away_points" => 0, "home_points" => 0,
                "start_situation" => { "down" => 1, "yfd" => 10, "location" => { "alias" => "UTAH", "yardline" => 25 } },
                "statistics" => [ { "stat_type" => "rush", "yards" => 10 } ] },
              { "type" => "event", "clock" => "14:30", "description" => "Timeout" }
            ] },
          { "type" => "play", "clock" => "00:00", "description" => "Standalone play" }
        ] },
        { "period_type" => "overtime", "number" => 1, "pbp" => [
          { "type" => "event", "description" => "Overtime event" }
        ] }
      ]
    }
    requested = []
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |id| requested << id; game }
    with_client(client) { get game_path("game-id", season: "2025") }

    assert_response :success
    assert_select ".brand img.brand-mark[alt=''][src*='utah-logo']", count: 1
    assert_equal [ "game-id" ], requested
    assert_select "a[href='/?season=2025']", text: /Back to schedule/
    assert_select ".scoreboard-team", text: /Utah Utes.*21/m
    assert_select ".scoreboard-team", text: /Idaho Vandals.*7/m
    assert_select ".scoreboard-status strong", text: "FINAL"
    assert_select ".period-nav a", count: 2
    assert_select "#period-1 .drive-heading", text: /Utah Utes drive.*2 plays.*10 yards/m
    assert_select ".game-event", count: 4
    assert_select ".game-event:nth-child(1)", text: /First play/
    assert_select ".event-meta", text: /1 & 10.*UTAH 25/
    assert_select ".game-event pre", text: /"stat_type": "rush"/
    assert_select ".replay[hidden]", count: 1
    assert_select ".game-event[data-replay-period='Quarter 1'][data-replay-away-score='0'][data-replay-home-score='0']", count: 1
    assert_select ".game-event[data-replay-period='Overtime 1'][data-replay-away-score=''][data-replay-home-score='']", count: 1
    assert_select "script[src*='replay']", count: 1
    assert_operator response.body.index("First play"), :<, response.body.index("Timeout")
    assert_operator response.body.index("Timeout"), :<, response.body.index("Standalone play")
    assert_operator response.body.index("Standalone play"), :<, response.body.index("Overtime event")
    assert_select "#period-heading-2", text: "Overtime 1"
  end

  test "displays an empty state for games without plays" do
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |_| { "status" => "scheduled", "periods" => [] } }
    with_client(client) { get game_path("game-id") }
    assert_response :success
    assert_select ".scoreboard-status strong", text: "SCHEDULED"
    assert_select ".state-message", text: /No play-by-play available yet/
    assert_select ".replay", count: 0
  end

  test "handles empty drives and does not expose invalid event scores to replay" do
    game = { "periods" => [
      { "number" => 1, "pbp" => [
        { "type" => "drive", "events" => [] },
        { "type" => "event", "description" => "Unsafe <script> text", "away_points" => -1, "home_points" => "7" }
      ] }
    ] }
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |_| game }
    with_client(client) { get game_path("game-id") }

    assert_select ".game-event", count: 1
    assert_select ".game-event[data-replay-away-score=''][data-replay-home-score='']", count: 1
    assert_select ".game-event p", text: "Unsafe <script> text"
    assert_select ".game-event script", count: 0
    assert_select ".period-empty", text: /No events available for this drive/
  end

  test "identifies historical drives without offensive team metadata" do
    game = {
      "summary" => {
        "home" => { "id" => "utah", "market" => "Utah", "name" => "Utes" },
        "away" => { "id" => "usc", "market" => "USC", "name" => "Trojans" }
      },
      "periods" => [ { "number" => 1, "pbp" => [
        { "type" => "drive", "end_reason" => "UNKNOWN", "events" => [
          { "type" => "play", "play_type" => "kickoff", "start_situation" => { "possession" => { "id" => "usc" } } },
          { "type" => "play", "play_type" => "punt", "start_situation" => { "possession" => { "id" => "utah" } },
            "end_situation" => { "possession" => { "id" => "usc" } } }
        ] },
        { "type" => "drive", "events" => [
          { "type" => "play", "play_type" => "pass", "start_situation" => { "possession" => { "id" => "usc" } } }
        ] }
      ] } ]
    }
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |_| game }
    with_client(client) { get game_path("game-id") }

    assert_response :success
    assert_select ".drive-heading", text: /Utah Utes drive.*Inferred: Punt/m
    assert_select ".drive-heading strong", text: "USC Trojans drive"
  end

  test "shows upstream errors with a season-preserving back link" do
    client = Object.new
    client.define_singleton_method(:game_play_by_play) { |_| raise Sportradar::Ncaafb::Client::RateLimitError, "Rate limited" }
    with_client(client) { get game_path("game-id", season: "2024") }
    assert_select "[role=alert]", text: /request limit/
    assert_select "a[href='/?season=2024']", text: /Back to schedule/

    client.define_singleton_method(:game_play_by_play) { |_| raise Sportradar::Ncaafb::Client::NotFoundError, "Not found" }
    with_client(client) { get game_path("game-id", season: "2024") }
    assert_select "[role=alert]", text: /not found/
  end
end
