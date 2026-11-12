require "test_helper"

class GamesHelperTest < ActionView::TestCase
  test "reconstructs synthetic historical drive segments across quarters" do
    periods = JSON.parse(file_fixture("historical_drives.json").read).fetch("periods")
    first = periods.first.fetch("pbp").first
    second = periods.last.fetch("pbp").first
    assert_equal "Continued in next period", drive_result(first, periods.first.fetch("pbp").drop(1), periods.last)
    assert_equal "Inferred: Interception", drive_result(second, [], nil)
  end

  setup do
    @summary = {
      "home" => { "id" => "utah", "market" => "Utah", "name" => "Utes" },
      "away" => { "id" => "usc", "market" => "USC", "name" => "Trojans" }
    }
  end

  def play(type, team, finish = nil)
    {
      "type" => "play", "play_type" => type,
      "start_situation" => { "possession" => team },
      "end_situation" => { "possession" => finish }
    }
  end

  test "uses the drive offense even when plays suggest another team" do
    drive = { "offensive_team" => { "id" => "utah" }, "events" => [ play("rush", { "id" => "usc" }) ] }
    assert_equal "Utah Utes", drive_team_name(drive, @summary)
  end

  test "uses the first non-kickoff play's starting possession" do
    drive = { "events" => [
      play("kickoff", { "id" => "usc" }, { "id" => "utah" }),
      play("rush", { "id" => "utah" }, { "id" => "usc" }),
      play("pass", { "id" => "usc" })
    ] }
    assert_equal "Utah Utes", drive_team_name(drive, @summary)
  end

  test "uses a team's supplied name when it is not in the summary" do
    drive = { "events" => [ play("pass", { "market" => "Example", "name" => "Team" }) ] }
    assert_equal "Example Team", drive_team_name(drive, @summary)
  end

  test "falls back when offensive team contains no identifiable team" do
    drive = { "offensive_team" => { "points" => 0 }, "events" => [ play("rush", { "id" => "utah" }) ] }
    assert_equal "Utah Utes", drive_team_name(drive, @summary)
  end

  test "leaves possession unknown when only kickoff or non-play events provide it" do
    drive = { "events" => [
      play("kickoff", { "id" => "usc" }, { "id" => "utah" }),
      { "type" => "event", "start_situation" => { "possession" => { "id" => "utah" } } },
      play("rush", nil)
    ] }
    assert_equal "Team TBD", drive_team_name(drive, @summary)
  end

  test "preserves a provided drive outcome" do
    assert_equal "Touchdown", drive_result({ "end_reason" => "Touchdown" }, [], nil)
    assert_equal "Result unavailable", drive_result({ "end_reason" => " UNKNOWN " }, [], nil)
  end

  test "infers punt, field goal, interception, and fumble outcomes" do
    punt = play("punt", { "id" => "utah" }, { "id" => "usc" })
    field_goal = play("field_goal", { "id" => "utah" }, { "id" => "utah" })
    interception = play("pass", { "id" => "utah" }, { "id" => "usc" })
    interception["details"] = [ { "category" => "pass_interception_return" } ]
    fumble = play("rush", { "id" => "utah" }, { "id" => "usc" })
    fumble["details"] = [ { "category" => "fumble" }, { "category" => "touchdown" } ]

    { "Inferred: Punt" => punt, "Inferred: Field goal attempt" => field_goal,
      "Inferred: Interception" => interception, "Inferred: Fumble lost" => fumble }.each do |expected, event|
      assert_equal expected, drive_result({ "end_reason" => "UNKNOWN", "events" => [ event ] }, [], nil)
    end
  end

  test "distinguishes made, blocked, and missed field goals when recorded" do
    event = play("field_goal", { "id" => "utah" }, { "id" => "utah" })
    { "made" => "Field goal made", "missed" => "Field goal missed", "blocked" => "Field goal blocked" }.each do |key, result|
      event["statistics"] = [ { "stat_type" => "field_goal", key => 1 } ]
      assert_equal "Inferred: #{result}", drive_result({ "events" => [ event ] }, [], nil)
    end
  end

  test "infers an offensive touchdown across the extra point but not a defensive score" do
    touchdown = play("rush", { "id" => "utah" }, { "id" => "utah" })
    touchdown["details"] = [ { "category" => "touchdown" } ]
    extra_point = play("extra_point", { "id" => "utah" }, { "id" => "utah" })
    assert_equal "Inferred: Touchdown", drive_result({ "events" => [ touchdown, extra_point ] }, [], nil)
    assert_equal "Inferred: Extra point attempt", drive_result({ "events" => [ extra_point ] }, [], nil)

    touchdown["end_situation"]["possession"] = { "id" => "usc" }
    assert_equal "Inferred: Extra point attempt", drive_result({ "events" => [ touchdown, extra_point ] }, [], nil)
  end

  test "handles turnover on downs, incomplete data and no-play penalties conservatively" do
    event = play("pass", { "id" => "utah" }, { "id" => "usc" })
    event["start_situation"]["down"] = 4
    assert_equal "Inferred: Turnover on downs", drive_result({ "events" => [ event ] }, [], nil)
    event["description"] = "Penalty enforced. No Play."
    assert_equal "Result unavailable", drive_result({ "events" => [ event ] }, [], nil)
    event["description"] = nil
    event["end_situation"]["possession"] = nil
    event["details"] = [ { "category" => "touchdown" } ]
    assert_equal "Result unavailable", drive_result({ "events" => [ event ] }, [], nil)
  end

  test "identifies continuation and period end without treating timeouts as a drive ending" do
    drive = { "id" => "drive-1", "events" => [ play("rush", { "id" => "utah" }, { "id" => "utah" }) ] }
    period_end = { "type" => "event", "event_type" => "period_end", "description" => "End of Quarter" }
    next_period = { "pbp" => [ { "type" => "drive", "id" => "drive-1" } ] }
    assert_equal "Continued in next period", drive_result(drive, [ period_end ], next_period)
    assert_equal "End of Quarter", drive_result(drive, [ period_end ], nil)
    assert_equal "Result unavailable", drive_result(drive, [ { "type" => "event", "event_type" => "timeout" } ], nil)
    assert_equal "Result unavailable", drive_result(drive, [ { "type" => "drive" }, period_end ], nil)
    assert_equal "Result unavailable", drive_result(drive, [ { "type" => "drive" }, period_end ], next_period)
  end
end
