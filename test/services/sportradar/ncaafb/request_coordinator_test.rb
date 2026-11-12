require "test_helper"
require "tmpdir"

class Sportradar::Ncaafb::RequestCoordinatorTest < ActiveSupport::TestCase
  setup do
    @directory = Pathname.new(Dir.mktmpdir("sportradar-locks"))
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  def coordinator(key = "key")
    Sportradar::Ncaafb::RequestCoordinator.new(api_key: key, access_level: "production", directory: @directory)
  end

  test "coalesces concurrent cache misses across coordinator instances" do
    cache = ActiveSupport::Cache::MemoryStore.new
    clients = 8.times.map do
      Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production", cache: cache, coordinator: coordinator)
    end
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    requests = Queue.new
    fake.define_singleton_method(:request) do |_|
      requests << true
      sleep 0.1
      Struct.new(:code, :body).new("200", '{"ok":true}')
    end
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      start = Queue.new
      threads = clients.map { |client| Thread.new { start.pop; client.league_hierarchy } }
      clients.size.times { start << true }
      assert_equal Array.new(8, { "ok" => true }), threads.map(&:value)
      assert_equal 1, requests.size
      assert_equal 1, clients.count { |client| client.request_metadata.first[:source] == :fetched }
      assert_equal 7, clients.count { |client| client.request_metadata.first[:source] == :cached }
      assert_equal 1, clients.map { |client| client.request_metadata.first[:fetched_at] }.uniq.size
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "persists cooldown across instances and rejects long inline waits" do
    coordinator.synchronize { |gate| gate.defer!(60) }
    error = assert_raises(Sportradar::Ncaafb::RequestCoordinator::Busy) do
      coordinator.synchronize { |gate| gate.wait! }
    end
    assert_match(/rate limited/, error.message)
    coordinator("other-key").synchronize { |gate| gate.wait! }
  end

  test "waits for a short cooldown before proceeding" do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    coordinator.synchronize { |gate| gate.defer!(0.1) }
    coordinator.synchronize { |gate| gate.wait! }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :>=, 0.09
  end

  test "limits lock wait and releases the lock after an error" do
    fast = Sportradar::Ncaafb::RequestCoordinator.new(
      api_key: "key", access_level: "production", directory: @directory, lock_wait_seconds: 0.1
    )
    coordinator.synchronize do
      assert_raises(Sportradar::Ncaafb::RequestCoordinator::Busy) { fast.synchronize { nil } }
    end
    assert_raises(RuntimeError) { fast.synchronize { raise "request failed" } }
    fast.synchronize { |gate| gate.wait! }
  end

  test "coordinates locks between processes" do
    ready_read, ready_write = IO.pipe
    done_read, done_write = IO.pipe
    child = nil
    coordinator.synchronize do
      child = fork do
        ready_read.close
        done_read.close
        ready_write.write("ready")
        ready_write.close
        coordinator.synchronize { done_write.write("done") }
        done_write.close
        exit! 0
      end
      ready_write.close
      done_write.close
      assert_equal "ready", ready_read.read(5)
      assert_nil IO.select([ done_read ], nil, nil, 0.15)
    end
    assert_equal "done", done_read.read(4)
    _, status = Process.wait2(child)
    child = nil
    assert status.success?
  ensure
    [ ready_read, ready_write, done_read, done_write ].each { |io| io.close unless io.closed? }
    Process.wait(child) if child
  end
end
