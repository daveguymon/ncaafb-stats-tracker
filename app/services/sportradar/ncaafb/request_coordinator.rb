require "digest"
require "fileutils"
require "json"
require "tempfile"

module Sportradar
  module Ncaafb
    class RequestCoordinator
      class Busy < StandardError; end
      class VisitorBusy < StandardError; end
      class StateError < StandardError; end

      LOCK_WAIT_SECONDS = 20
      MAX_INLINE_WAIT_SECONDS = 2
      POLL_INTERVAL = 0.05

      def initialize(api_key:, access_level:, directory: Rails.root.join("storage/sportradar_locks"),
                     lock_wait_seconds: LOCK_WAIT_SECONDS)
        digest = Digest::SHA256.hexdigest("#{access_level}\0#{api_key}")
        @path = directory.join("#{digest}.lock")
        @state_path = directory.join("#{digest}.json")
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
          yield Gate.new(file, @state_path)
        ensure
          file.flock(File::LOCK_UN)
        end
      end

      class Gate
        STATE_MARKER = "state-v2".freeze

        def initialize(file, state_path)
          @file = file
          @state_path = state_path
        end

        def wait!
          wait = state.fetch("cooldown_until") - Time.now.to_f
          raise Busy, "Sportradar is rate limited; try again later" if wait > MAX_INLINE_WAIT_SECONDS

          sleep(wait) if wait.positive?
        end

        def reserve!(limit:, window_seconds:, visitor_key: nil, visitor_limit: nil, visitor_window_seconds: nil)
          return unless limit || visitor_key

          now = Time.now.to_f
          current = state
          requests = current.fetch("requests")
          if limit
            requests = requests.select { |timestamp| timestamp > now - window_seconds }
            raise Busy, "Sportradar request budget exhausted; try again later" if requests.size >= limit
            requests << now
          end

          if visitor_key
            visitors = current.fetch("visitors", {}).transform_values do |timestamps|
              timestamps.select { |timestamp| timestamp > now - visitor_window_seconds }
            end.reject { |_, timestamps| timestamps.empty? }
            attempts = visitors.fetch(visitor_key, [])
            raise VisitorBusy, "Too many requests from this visitor; try again later" if attempts.size >= visitor_limit

            visitors[visitor_key] = attempts << now
            current["visitors"] = visitors
          end

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
          unless @state_path.exist?
            @file.rewind
            legacy = @file.read
            raise StateError, "Sportradar request coordination state is missing" if legacy == STATE_MARKER

            current = legacy.empty? ? { "cooldown_until" => 0, "requests" => [] } : parse_state(legacy)
            write_state(current)
            mark_migrated
            return current
          end

          current = parse_state(@state_path.read)
          mark_migrated
          current
        end

        def mark_migrated
          @file.rewind
          return if @file.read == STATE_MARKER

          @file.rewind
          @file.write(STATE_MARKER)
          @file.truncate(@file.pos)
          @file.flush
          @file.fsync
        end

        def parse_state(value)
          parsed = JSON.parse(value)
          return { "cooldown_until" => parsed, "requests" => [] } if parsed.is_a?(Numeric) && parsed.finite?

          if parsed.is_a?(Hash) && parsed["cooldown_until"].is_a?(Numeric) && parsed["cooldown_until"].finite? &&
              valid_timestamps?(parsed["requests"]) &&
              (!parsed.key?("visitors") || (parsed["visitors"].is_a?(Hash) &&
                parsed["visitors"].all? { |key, times| key.is_a?(String) && valid_timestamps?(times) }))
            return parsed
          end

          raise StateError, "Sportradar request coordination state is invalid"
        rescue JSON::ParserError
          raise StateError, "Sportradar request coordination state is invalid"
        end

        def valid_timestamps?(value)
          value.is_a?(Array) && value.all? { |time| time.is_a?(Numeric) && time.finite? }
        end

        def write_state(current)
          Tempfile.create([ ".sportradar-state-", ".tmp" ], @state_path.dirname) do |temp|
            temp.write(JSON.generate(current))
            temp.flush
            temp.fsync
            File.rename(temp.path, @state_path)
            File.open(@state_path.dirname) { |directory| directory.fsync }
          end
        end
      end
    end
  end
end
