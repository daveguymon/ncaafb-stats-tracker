require "test_helper"

class Sportradar::Ncaafb::DriveTeamTest < ActiveSupport::TestCase
  setup do
    @utah = { "id" => "utah", "market" => "Utah", "name" => "Utes" }
    @usc = { "id" => "usc", "market" => "USC", "name" => "Trojans" }
    @summary = { "home" => @utah, "away" => @usc }
  end

  def play(type, possession)
    { "type" => "play", "play_type" => type, "start_situation" => { "possession" => possession } }
  end

  test "prefers explicit offense and resolves its ID against the summary" do
    drive = { "offensive_team" => { "id" => "utah" }, "events" => [ play("rush", { "id" => "usc" }) ] }
    assert_equal @utah, Sportradar::Ncaafb::DriveTeam.call(drive, @summary)
  end

  test "falls back to the first non-kickoff play with possession" do
    drive = { "offensive_team" => { "points" => 0 }, "events" => [
      play("kickoff", { "id" => "usc" }), play("rush", { "id" => "utah" }), play("pass", { "id" => "usc" })
    ] }
    assert_equal @utah, Sportradar::Ncaafb::DriveTeam.call(drive, @summary)
  end

  test "uses a supplied name and does not invent an unidentified team" do
    other = { "id" => "other", "alias" => "OTHER" }
    assert_equal other, Sportradar::Ncaafb::DriveTeam.call({ "offensive_team" => other }, @summary)
    drive = { "events" => [ play("kickoff", { "id" => "usc" }), play("rush", { "id" => "unknown" }) ] }
    assert_nil Sportradar::Ncaafb::DriveTeam.call(drive, @summary)
    assert_nil Sportradar::Ncaafb::DriveTeam.call({}, @summary)
  end
end
