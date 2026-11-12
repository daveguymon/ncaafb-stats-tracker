require "application_system_test_case"

class DemoNavigationTest < ApplicationSystemTestCase
  setup do
    @previous_mode = ENV["DEMO_MODE"]
    ENV["DEMO_MODE"] = "true"
  end

  teardown do
    ENV["DEMO_MODE"] = @previous_mode
  end

  test "navigates the demo schedule and controls replay with the keyboard" do
    visit root_path
    assert_text "Synthetic, abbreviated sample data"
    assert_selector "label[for='season']", text: "SEASON YEAR"
    assert_text "Sample City, UT"
    click_link "View play-by-play"

    assert_text "FINAL"
    assert_selector "section[aria-labelledby='replay-heading']"
    assert_selector "[data-replay-position][aria-valuetext='Before first event']"
    find("[data-replay-action='next']").send_keys(:enter)
    assert_text "Event 1 of 5"
    assert_selector "[data-replay-position][aria-valuetext='Event 1 of 5']"
    assert_text "Event score: away 0"
    click_link "View this event in the full list"
    assert_selector "#replay-event-1.replay-selected"
    click_link "Back to schedule"
    assert_selector "input[name='season'][value='2024']"
  end

  test "reports a season unavailable in demo mode" do
    visit root_path
    fill_in "SEASON YEAR", with: "2023"
    click_button "View schedule"
    assert_selector "[role='alert']", text: "Demo data is available only for the 2024 season."
  end
end
