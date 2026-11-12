require "digest"
require "fileutils"
require "json"

module Sportradar
  module Ncaafb
    class RequestCoordinator
      class Busy < StandardError; end
      class StateError < StandardError; end

      LOCK_WAIT_SECONDS = 20
      MAX_INLINE_WAIT_SECONDS = 2
      POLL_INTERVAL = 0.05

      def initialize(api_key:, access_level:, directory: Rails.root.join("storage/sportradar_locks"),
                     lock_wait_seconds: LOCK_WAIT_SECONDS)
        digest = Digest::SHA256.hexdigest("#{access_level}\0#{api_key}")
        @path = directory.join("#{digest}.lock")
        @lock_wait_seconds = lock_wait_seconds
      end

      def synchronize
        FileUtils.mkdir_p(@path.dirname)
        File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @lock_wait_seconds
          until file.flock(File::LOCK_EX | File::LOCK_NB)
            raise Busy, "Sportradar requests are busy; try again shortly" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            sleep POLL_INTERVAL
          end
          yield Gate.new(file)
        ensure
          file.flock(File::LOCK_UN)
        end
      end

      class Gate
        def initialize(file)
          @file = file
        end

        def wait!
          wait = state.fetch("cooldown_until") - Time.now.to_f
          raise Busy, "Sportradar is rate limited; try again later" if wait > MAX_INLINE_WAIT_SECONDS

          sleep(wait) if wait.positive?
        end

        def reserve!(limit:, window_seconds:)
          return unless limit

          now = Time.now.to_f
          current = state
          requests = current.fetch("requests").select { |timestamp| timestamp > now - window_seconds }
          raise Busy, "Sportradar request budget exhausted; try again later" if requests.size >= limit

          requests << now
          current["requests"] = requests
          write_state(current)
        end

        def defer!(seconds)
          current = state
          current["cooldown_until"] = Time.now.to_f + seconds
          write_state(current)
        end

        private

        def state
          @file.rewind
          value = @file.read
          return { "cooldown_until" => 0, "requests" => [] } if value.empty?

          parsed = JSON.parse(value)
          return { "cooldown_until" => parsed, "requests" => [] } if parsed.is_a?(Numeric) && parsed.finite?

          if parsed.is_a?(Hash) && parsed["cooldown_until"].is_a?(Numeric) && parsed["cooldown_until"].finite? &&
              parsed["requests"].is_a?(Array) && parsed["requests"].all? { |time| time.is_a?(Numeric) && time.finite? }
            return parsed
          end

          raise StateError, "Sportradar request coordination state is invalid"
        rescue JSON::ParserError
          raise StateError, "Sportradar request coordination state is invalid"
        end

        def write_state(current)
          @file.rewind
          @file.write(JSON.generate(current))
          @file.truncate(@file.pos)
          @file.flush
          @file.fsync
        end
      end
    end
  end
end
