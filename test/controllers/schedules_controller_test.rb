require "test_helper"

class SchedulesControllerTest < ActionDispatch::IntegrationTest
  def with_client(client)
    original = Sportradar::Ncaafb::Client.method(:new)
    Sportradar::Ncaafb::Client.define_singleton_method(:new) { client }
    yield
  ensure
    Sportradar::Ncaafb::Client.define_singleton_method(:new, original)
  end

  test "defaults to Utah and current season and orders games by date" do
    games = [
      { "id" => "unknown", "home" => { "id" => "utah" }, "away" => { "name" => "Unknown date opponent" } },
      { "id" => "tbd", "status" => "time-tbd", "scheduled" => "2026-09-10T00:00:00Z", "home" => { "id" => "utah" }, "away" => { "name" => "TBD opponent" } },
      { "id" => "late", "status" => "scheduled", "scheduled" => "2026-10-10T18:00:00Z", "away" => { "id" => "utah" }, "home" => { "name" => "Later opponent" } },
      { "id" => "early", "scheduled" => "2026-09-05T18:00:00Z", "status" => "closed",
        "home" => { "id" => "utah", "name" => "Utah Utes" }, "away" => { "id" => "opponent", "name" => "Early opponent" },
        "week" => "1", "season_type" => "REG", "scoring" => { "home_points" => 28, "away_points" => 14 } }
    ]
    requested_years = []
    client = Object.new
    utah_id = Sportradar::Ncaafb::Teams::UTAH[:id]
    games.each { |game| %w[home away].each { |side| game[side]["id"] = utah_id if game[side]&.dig("id") == "utah" } }
    client.define_singleton_method(:season_games) { |year| requested_years << year; games }

    travel_to Time.utc(2026, 11, 1) do
      with_client(client) { get root_path }
    end

    assert_response :success
    assert_equal [ "2026" ], requested_years
    assert_select "input[name=season][value='2026']"
    assert_select ".team-selection", text: /Utah Utes/
    assert_select ".game-card", count: 4
    assert_select ".game-card:first-child", text: /Early opponent/
    assert_select ".game-card:last-child", text: /Date TBD/
    assert_select ".game-card:nth-child(2)", text: /TBD opponent.*Kickoff TBD|Kickoff TBD.*TBD opponent/m
    assert_select ".game-card:first-child", text: /WEEK 1/
    assert_select ".game-card:first-child", text: /14.*28/m
    assert_select ".game-card:first-child .status", text: "FINAL"
    assert_select ".game-card:nth-child(2) .status", text: "TIME TBD"
    assert_select ".game-card:nth-child(3) .status", text: "SCHEDULED"
    assert_select ".game-card:last-child .status", text: "STATUS TBD"
    assert_select ".game-card:first-child details pre", text: /"status": "closed"/
    assert_select ".game-card:first-child .team-record[aria-label='Record entering game: 0-0']", text: "0-0", count: 2
    assert_select ".game-card:nth-child(2) .team-record", text: "1-0"
    assert_select ".game-card:last-child .team-record", text: "Record unavailable", count: 2
    assert_select "details pre", text: /"id": "early"/
    assert_select "a[href='/games/early?season=2026']", text: /View play-by-play/
  end

  test "selects another season and displays an empty schedule" do
    client = Object.new
    client.define_singleton_method(:season_games) { |year| year == "2010" ? [] : raise("Unexpected season") }
    with_client(client) { get root_path, params: { season: "2010" } }

    assert_response :success
    assert_select "input[name=season][value='2010']"
    assert_select ".state-message", text: /No games found/
  end

  test "rejects invalid input without calling Sportradar" do
    client = Object.new
    with_client(client) { get root_path, params: { season: "abc" } }
    assert_select "[role=alert]", text: /four-digit/
    with_client(client) { get root_path, params: { season: [ "2026" ] } }
    assert_select "[role=alert]", text: /four-digit/
  end

  test "displays rate limit and missing schedule errors" do
    client = Object.new
    client.define_singleton_method(:season_games) { |_| raise Sportradar::Ncaafb::Client::RateLimitError, "Rate limited" }
    with_client(client) { get root_path, params: { season: "2026" } }
    assert_select "[role=alert]", text: /request limit/

    client.define_singleton_method(:season_games) { |_| raise Sportradar::Ncaafb::Client::NotFoundError, "Not found" }
    with_client(client) { get root_path, params: { season: "2001" } }
    assert_select "[role=alert]", text: /2001.*not found/
  end
end
