require "test_helper"

class SchedulesHelperTest < ActionView::TestCase
  test "formats wins, losses, and ties only when present" do
    assert_equal "2-1", schedule_record({ wins: 2, losses: 1, ties: 0 })
    assert_equal "2-1-1", schedule_record({ wins: 2, losses: 1, ties: 1 })
    assert_equal "Record unavailable", schedule_record(nil)
    assert_equal "2-1 (coverage unverified)", schedule_record({ wins: 2, losses: 1, ties: 0 }, coverage: :unverified)
  end
end
