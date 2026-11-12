require "test_helper"

class Sportradar::Ncaafb::SeasonRecordsTest < ActiveSupport::TestCase
  def game(id, date, home, away, home_points: nil, away_points: nil, status: "closed", season_type: "REG")
    {
      "id" => id, "scheduled" => date, "status" => status, "season_type" => season_type,
      "home" => { "id" => home }, "away" => { "id" => away },
      "scoring" => { "home_points" => home_points, "away_points" => away_points }
    }
  end

  test "calculates records before games from all teams, including ties and postseason" do
    opponent_win = game("a", "2025-08-25T18:00:00Z", "opponent", "other", home_points: 14, away_points: 7)
    utah_win = game("b", "2025-09-01T18:00:00Z", "utah", "other", home_points: 28, away_points: 7)
    target = game("c", "2025-09-08T18:00:00Z", "utah", "opponent", home_points: 10, away_points: 10)
    upcoming = game("d", "2025-12-01T18:00:00Z", "opponent", "utah", status: "scheduled", season_type: "PST")
    games = [ upcoming, target, utah_win, opponent_win ]
    records = Sportradar::Ncaafb::SeasonRecords.new(games).for_games([ target, upcoming ])

    assert_equal({ wins: 1, losses: 0, ties: 0 }, records[target.object_id]["home"])
    assert_equal({ wins: 1, losses: 0, ties: 0 }, records[target.object_id]["away"])
    assert_equal({ wins: 1, losses: 0, ties: 1 }, records[upcoming.object_id]["home"])
    assert_equal({ wins: 1, losses: 0, ties: 1 }, records[upcoming.object_id]["away"])
  end

  test "excludes live, cancelled, and future results and includes postseason results" do
    first = game("a", "2025-12-10T18:00:00Z", "utah", "other", home_points: 7, away_points: 10, season_type: "PST")
    live = game("b", "2025-12-11T18:00:00Z", "utah", "other", home_points: 20, away_points: 0, status: "inprogress")
    cancelled = game("c", "2025-12-12T18:00:00Z", "utah", "other", status: "cancelled")
    target = game("d", "2025-12-13T18:00:00Z", "utah", "other", status: "scheduled", season_type: "PST")
    later = game("e", "2025-12-14T18:00:00Z", "utah", "other", home_points: 20, away_points: 0)
    records = Sportradar::Ncaafb::SeasonRecords.new([ first, live, cancelled, target, later ]).for_games([ target ])
    assert_equal({ wins: 0, losses: 1, ties: 0 }, records[target.object_id]["home"])
  end

  test "does not invent records when required information is missing" do
    first = game("a", "2025-09-01T18:00:00Z", "utah", "other")
    target = game("b", "2025-09-08T18:00:00Z", "utah", "opponent", status: "scheduled")
    target["away"].delete("id")
    records = Sportradar::Ncaafb::SeasonRecords.new([ first, target ]).for_games([ target ])
    assert_nil records[target.object_id]["home"]
    assert_nil records[target.object_id]["away"]

    first["scheduled"] = nil
    records = Sportradar::Ncaafb::SeasonRecords.new([ first, target ]).for_games([ target ])
    assert_nil records[target.object_id]["home"]

    target["scheduled"] = nil
    assert_nil Sportradar::Ncaafb::SeasonRecords.new([ target ]).for_games([ target ])[target.object_id]["home"]
  end

  test "marks missing prior games and ambiguous same-day kickoff records unavailable" do
    target = game("b", "2025-09-08T18:00:00Z", "utah", "opponent", home_points: 7, away_points: 3)
    target["home"]["game_number"] = 2
    assert_nil Sportradar::Ncaafb::SeasonRecords.new([ target ]).for_games([ target ])[target.object_id]["home"]

    earlier = game("a", "2025-09-08T12:00:00Z", "utah", "other", home_points: 7, away_points: 3)
    target["status"] = "time-tbd"
    assert_nil Sportradar::Ncaafb::SeasonRecords.new([ earlier, target ]).for_games([ target ])[target.object_id]["home"]
  end
end
