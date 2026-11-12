require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "formats game statuses consistently without changing the source value" do
    status = "closed"
    assert_equal "FINAL", game_status_label(status)
    assert_equal "closed", status
    assert_equal "TIME TBD", game_status_label("time-tbd")
    assert_equal "IN PROGRESS", game_status_label("in_progress")
    assert_equal "STATUS TBD", game_status_label(nil)
    assert_equal "STATUS TBD", game_status_label("")
  end
end
