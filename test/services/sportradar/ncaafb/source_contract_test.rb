require "test_helper"

class Sportradar::Ncaafb::SourceContractTest < ActiveSupport::TestCase
  test "live and demo sources normalize and filter schedules consistently" do
    utah = Sportradar::Ncaafb::Teams::UTAH[:id]
    schedule = { "weeks" => [
      { "sequence" => 3, "games" => [
        { "id" => "utah-game", "home" => { "id" => utah }, "away" => { "id" => "other" } },
        { "id" => "other-game", "home" => { "id" => "a" }, "away" => { "id" => "b" } }
      ] }
    ] }
    sources = [
      Sportradar::Ncaafb::Client.new(api_key: "test"),
      Sportradar::Ncaafb::DemoClient.new
    ]
    sources.each do |source|
      source.define_singleton_method(:season_schedule) { |_, _| schedule }
      games = source.season_games(2024, season_types: "reg")
      assert_equal %w[utah-game other-game], games.map { |game| game["id"] }
      assert_equal [ 3, 3 ], games.map { |game| game["week"] }
      assert_equal [ "REG", "REG" ], games.map { |game| game["season_type"] }
      assert_equal [ "utah-game" ], source.team_games(2024, season_types: [ "REG" ]).map { |game| game["id"] }
    end
  end
end
