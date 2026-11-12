require "test_helper"

class Sportradar::Ncaafb::DataSourceFactoryTest < ActiveSupport::TestCase
  test "builds live clients with a stable keyed visitor digest" do
    keys = []
    client = Object.new
    factory = Sportradar::Ncaafb::DataSourceFactory.new(
      live_builder: ->(visitor_key:) { keys << visitor_key; client },
      demo_builder: -> { raise "Demo source must not be used" }
    )

    assert_same client, factory.build(demo: false, remote_ip: "192.0.2.1")
    factory.build(demo: false, remote_ip: "192.0.2.1")
    factory.build(demo: false, remote_ip: "192.0.2.2")
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "192.0.2.1"), keys.first
    assert_equal keys[0], keys[1]
    refute_equal keys[0], keys[2]
    refute_includes keys.first, "192.0.2.1"
  end

  test "builds demo source without constructing a live client or using an IP address" do
    demo = Object.new
    factory = Sportradar::Ncaafb::DataSourceFactory.new(
      live_builder: ->(visitor_key:) { raise "Live source must not be used" },
      demo_builder: -> { demo }
    )
    assert_same demo, factory.build(demo: true, remote_ip: nil)
    assert_instance_of Sportradar::Ncaafb::DemoClient,
      Sportradar::Ncaafb::DataSourceFactory.new.build(demo: true, remote_ip: nil)
  end
end
