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
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
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

  test "enforces a rolling budget across instances and keeps cooldowns independent" do
    travel_to Time.utc(2026, 11, 12, 12) do
      coordinator.synchronize { |gate| gate.reserve!(limit: 2, window_seconds: 60) }
      coordinator.synchronize do |gate|
        gate.reserve!(limit: 2, window_seconds: 60)
        gate.defer!(0)
      end
      assert_raises(Sportradar::Ncaafb::RequestCoordinator::Busy) do
        coordinator.synchronize { |gate| gate.reserve!(limit: 2, window_seconds: 60) }
      end
      coordinator("other-key").synchronize { |gate| gate.reserve!(limit: 2, window_seconds: 60) }
    end
    travel_to Time.utc(2026, 11, 12, 12, 1) do
      coordinator.synchronize { |gate| gate.reserve!(limit: 2, window_seconds: 60) }
    end
  end

  test "shares the rolling budget with another process" do
    coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    reader, writer = IO.pipe
    child = fork do
      reader.close
      begin
        coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
        writer.write("allowed")
      rescue Sportradar::Ncaafb::RequestCoordinator::Busy
        writer.write("blocked")
      ensure
        writer.close
      end
      exit! 0
    end
    writer.close
    assert_equal "blocked", reader.read
    _, status = Process.wait2(child)
    child = nil
    assert status.success?
  ensure
    reader.close unless reader.closed?
    writer.close unless writer.closed?
    Process.wait(child) if child
  end

  test "limits individual visitors while allowing cached responses and other visitors" do
    cache = ActiveSupport::Cache::MemoryStore.new
    build_client = ->(visitor) {
      Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
        cache: cache, coordinator: coordinator, visitor_key: visitor,
        quota_limit: 100, quota_window_seconds: 600)
    }
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    attempts = 0
    fake.define_singleton_method(:request) { |_| attempts += 1; Struct.new(:code, :body).new("200", '{"ok":true}') }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      travel_to Time.utc(2026, 11, 12, 12) do
        visitor = build_client.call("visitor-a")
        25.times { |index| visitor.game_summary("game-#{index}") }
        assert_equal({ "ok" => true }, visitor.game_summary("game-0"))
        assert_raises(Sportradar::Ncaafb::Client::VisitorRateLimitError) { visitor.game_summary("next") }
        assert_equal 25, attempts
        assert_equal({ "ok" => true }, build_client.call("visitor-b").game_summary("next"))
      end
      travel_to Time.utc(2026, 11, 12, 12, 2) do
        assert_equal({ "ok" => true }, build_client.call("visitor-a").game_summary("after-window"))
      end
      assert_equal 27, attempts
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "migrates a legacy cooldown and rejects corrupt coordination state" do
    path = @directory.join("#{Digest::SHA256.hexdigest("production\0key")}.lock")
    File.write(path, "0.0")
    coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    assert_raises(Sportradar::Ncaafb::RequestCoordinator::Busy) do
      coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    end
    File.write(path.sub_ext(".json"), "{invalid")
    assert_raises(Sportradar::Ncaafb::RequestCoordinator::StateError) do
      coordinator.synchronize { |gate| gate.wait! }
    end
  end

  test "rejects missing or empty state after initialization" do
    coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    state_path = @directory.join("#{Digest::SHA256.hexdigest("production\0key")}.json")
    File.write(state_path, "")
    assert_raises(Sportradar::Ncaafb::RequestCoordinator::StateError) do
      coordinator.synchronize { |gate| gate.wait! }
    end
    File.unlink(state_path)
    assert_raises(Sportradar::Ncaafb::RequestCoordinator::StateError) do
      coordinator.synchronize { |gate| gate.wait! }
    end
  end

  test "retains previous state when atomic replacement fails" do
    coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    original = File.method(:rename)
    File.define_singleton_method(:rename) { |*| raise Errno::EIO }
    begin
      assert_raises(Errno::EIO) { coordinator.synchronize { |gate| gate.defer!(60) } }
    ensure
      File.define_singleton_method(:rename, original)
    end
    assert_raises(Sportradar::Ncaafb::RequestCoordinator::Busy) do
      coordinator.synchronize { |gate| gate.reserve!(limit: 1, window_seconds: 60) }
    end
  end

  test "counts concurrent cache misses against the same budget" do
    clients = 8.times.map do
      Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
        cache: ActiveSupport::Cache::MemoryStore.new, coordinator: coordinator,
        quota_limit: 3, quota_window_seconds: 60)
    end
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    requests = Queue.new
    fake.define_singleton_method(:request) { |_| requests << true; Struct.new(:code, :body).new("200", '{"ok":true}') }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      threads = clients.map do |client|
        Thread.new do
          client.league_hierarchy
          :allowed
        rescue Sportradar::Ncaafb::Client::RateLimitError
          :blocked
        end
      end
      results = threads.map(&:value)
      assert_equal 3, results.count(:allowed)
      assert_equal 5, results.count(:blocked)
      assert_equal 3, requests.size
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "does not retry a failed connection outside the budget" do
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator,
      quota_limit: 1, quota_window_seconds: 60)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    attempts = 0
    fake.define_singleton_method(:request) { |_| attempts += 1; raise EOFError }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_raises(Sportradar::Ncaafb::Client::Error) { client.league_hierarchy }
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.league_hierarchy }
      assert_equal 1, attempts
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "counts upstream failures and retries but serves cached responses after exhaustion" do
    cache = ActiveSupport::Cache::MemoryStore.new
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: cache, coordinator: coordinator, quota_limit: 2, quota_window_seconds: 60)
    responses = [
      Struct.new(:code, :body).new("200", '{"ok":true}'),
      Struct.new(:code, :body).new("429", "")
    ]
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| responses.shift }
    responses.last.define_singleton_method(:[]) { |_| "0" }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_equal({ "ok" => true }, client.league_hierarchy)
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.game_summary("game") }
      assert_empty responses
      assert_equal({ "ok" => true }, client.league_hierarchy)
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.game_summary("other") }
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "counts a not-found response against the budget" do
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator,
      quota_limit: 1, quota_window_seconds: 60)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    requests = Queue.new
    fake.define_singleton_method(:request) { |_| requests << true; Struct.new(:code, :body).new("404", "") }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_raises(Sportradar::Ncaafb::Client::NotFoundError) { client.league_hierarchy }
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.league_hierarchy }
      assert_equal 1, requests.size
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "counts each retry even when the retry succeeds" do
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator,
      quota_limit: 2, quota_window_seconds: 60)
    rate_limited = Struct.new(:code, :body).new("429", "")
    rate_limited.define_singleton_method(:[]) { |_| "0" }
    responses = [ rate_limited, Struct.new(:code, :body).new("200", '{"ok":true}') ]
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| responses.shift }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_equal({ "ok" => true }, client.league_hierarchy)
      assert_empty responses
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.league_hierarchy }
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "counts a failed network attempt against the budget" do
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator,
      quota_limit: 1, quota_window_seconds: 60)
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |_| }
    fake.define_singleton_method(:open_timeout=) { |_| }
    fake.define_singleton_method(:read_timeout=) { |_| }
    fake.define_singleton_method(:max_retries=) { |value| raise "Implicit HTTP retries enabled" unless value == 0 }
    fake.define_singleton_method(:request) { |_| raise Errno::ECONNRESET }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake }
    begin
      assert_raises(Sportradar::Ncaafb::Client::Error) { client.league_hierarchy }
      assert_raises(Sportradar::Ncaafb::Client::RateLimitError) { client.league_hierarchy }
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "surfaces corrupt coordination state as an error without making a request" do
    path = @directory.join("#{Digest::SHA256.hexdigest("production\0key")}.lock")
    File.write(path, "{invalid")
    client = Sportradar::Ncaafb::Client.new(api_key: "key", access_level: "production",
      cache: ActiveSupport::Cache::NullStore.new, coordinator: coordinator,
      quota_limit: 1, quota_window_seconds: 60)
    error = assert_raises(Sportradar::Ncaafb::Client::Error) { client.league_hierarchy }
    assert_match(/coordination failed/, error.message)
  end
end
