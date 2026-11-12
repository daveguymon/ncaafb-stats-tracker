require "test_helper"

class SchedulesHelperTest < ActionView::TestCase
  test "formats wins, losses, and ties only when present" do
    assert_equal "2-1", schedule_record(wins: 2, losses: 1, ties: 0)
    assert_equal "2-1-1", schedule_record(wins: 2, losses: 1, ties: 1)
    assert_equal "Record unavailable", schedule_record(nil)
  end
end
