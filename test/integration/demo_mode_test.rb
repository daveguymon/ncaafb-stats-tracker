require "test_helper"
require_relative "../support/data_source_injection"

class DemoModeTest < ActionDispatch::IntegrationTest
  include DataSourceInjection

  setup do
    @previous_mode = ENV["DEMO_MODE"]
    @previous_key = ENV["SPORTRADAR_API_KEY"]
    @previous_limit = ENV["SPORTRADAR_QUOTA_LIMIT"]
    ENV["DEMO_MODE"] = "true"
    ENV.delete("SPORTRADAR_API_KEY")
    ENV.delete("SPORTRADAR_QUOTA_LIMIT")
    @test_data_source_factory = Sportradar::Ncaafb::DataSourceFactory.new(
      live_builder: ->(visitor_key:) { raise "Live client must not be used in demo mode" }
    )
  end

  teardown do
    ENV["DEMO_MODE"] = @previous_mode
    ENV["SPORTRADAR_API_KEY"] = @previous_key
    ENV["SPORTRADAR_QUOTA_LIMIT"] = @previous_limit
  end

  test "navigates the synthetic schedule and abbreviated game without an API key" do
    get root_path
    assert_response :success
    assert_select ".demo-banner", text: /Synthetic.*not a real Utah game.*No Sportradar requests/
    assert_select "input[name=season][value='2024']"
    assert_select ".game-card", count: 1
    assert_select ".game-card", text: /Sample State/
    assert_select ".game-card .game-venue", text: /Illustrative stadium/
    assert_select ".game-card .game-venue small", text: "Sample City, UT"
    assert_select ".game-card .team-record", text: "0-0", count: 2
    assert_select ".flow", text: /Bundled sample/
    assert_select ".flow li:first-child", text: /Season year.*Utah Utes.*2024/m
    assert_select ".team-info", text: /This tracker covers Utah football/
    assert_no_match(/Selected team|Your selection/i, response.body)
    assert_select ".freshness", count: 0
    assert_select ".data-source", text: /SYNTHETIC DEMO DATA/

    get game_path("demo-utah-sample-state", season: "2024")
    assert_response :success
    assert_select ".demo-banner", text: /not a real Utah game/
    assert_select ".scoreboard-team", text: /Utah Utes.*7/m
    assert_select ".period-nav a", count: 4
    assert_select ".game-event", text: /Illustrative 75-yard touchdown pass/
    assert_select ".game-event pre", text: /"yards": 75/
    assert_select ".results-subtitle", text: /not a complete play-by-play/
    assert_select "a[href='/?season=2024']", text: /Back to schedule/
    assert_select ".freshness", count: 0
  end

  test "unavailable seasons and games stay in demo mode" do
    get root_path, params: { season: "2023" }
    assert_select "[role=alert]", text: /only for the 2024 season/
    assert_select ".demo-banner", count: 1
    get game_path("real-game")
    assert_select "[role=alert]", text: /not available in the demo/
    assert_select ".demo-banner", count: 1
  end

  test "disabling demo mode uses the live client without demo labels" do
    ENV["DEMO_MODE"] = "false"
    fake = Object.new
    fake.define_singleton_method(:season_games) { |_, **| [] }
    fake.define_singleton_method(:request_metadata) { [] }
    fake.define_singleton_method(:league_hierarchy) { { "live" => true } }
    with_client(fake) do
      get root_path, params: { season: "2024" }
      assert_response :success
      assert_select ".demo-banner", count: 0
      assert_select ".flow", text: /Sportradar API/
      get "/sportradar/hierarchy"
      assert_response :success
      assert_equal({ "live" => true }, response.parsed_body)
      assert_nil response.headers["X-Data-Source"]
    end
  end

  test "JSON endpoints identify demo data and never fall back to live" do
    get "/sportradar/schedule/2024/REG"
    assert_response :success
    assert_equal "demo", response.headers["X-Data-Source"]
    assert_equal "demo-utah-sample-state", response.parsed_body.dig("weeks", 0, "games", 0, "id")

    get "/sportradar/schedule/2024/PST"
    assert_response :success
    assert_equal [], response.parsed_body["weeks"]

    get "/sportradar/utah/games/2024"
    assert_response :success
    assert_equal [ "demo-utah-sample-state" ], response.parsed_body.map { |game| game["id"] }

    get "/sportradar/games/demo-utah-sample-state/pbp"
    assert_response :success
    assert_equal 4, response.parsed_body.fetch("periods").size
    assert_equal "demo", response.headers["X-Data-Source"]

    %w[/sportradar/hierarchy /sportradar/schedule/2023/REG /sportradar/schedule/2024/PRE /sportradar/games/real/pbp
       /sportradar/games/demo-utah-sample-state /sportradar/games/demo-utah-sample-state/statistics].each do |path|
      get path
      assert_response :not_found
      assert_equal "demo", response.headers["X-Data-Source"]
      assert_match(/demo mode/, response.parsed_body["error"])
    end
    get "/sportradar/schedule/2024/INVALID"
    assert_response :bad_request
    assert_equal "demo", response.headers["X-Data-Source"]
  end
end
