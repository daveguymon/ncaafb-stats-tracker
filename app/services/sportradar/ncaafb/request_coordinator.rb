require "digest"
require "fileutils"

module Sportradar
  module Ncaafb
    class RequestCoordinator
      class Busy < StandardError; end

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
          @file.rewind
          value = @file.read
          wait = value.empty? ? 0 : Float(value) - Time.now.to_f
          raise Busy, "Sportradar is rate limited; try again later" if wait > MAX_INLINE_WAIT_SECONDS

          sleep(wait) if wait.positive?
        end

        def defer!(seconds)
          @file.rewind
          @file.write((Time.now.to_f + seconds).to_s)
          @file.truncate(@file.pos)
          @file.flush
        end
      end
    end
  end
end
