require "test_helper"

class Sportradar::Ncaafb::DriveResultTest < ActiveSupport::TestCase
  test "preserves explicit results and does not infer a turnover without a possession change" do
    service = Sportradar::Ncaafb::DriveResult
    assert_equal "Touchdown", service.call({ "end_reason" => "Touchdown" }, [], nil)
    play = { "type" => "play", "play_type" => "pass",
      "details" => [ { "category" => "interception" } ] }
    assert_equal "Result unavailable", service.call({ "events" => [ play ] }, [], nil)
  end
end
