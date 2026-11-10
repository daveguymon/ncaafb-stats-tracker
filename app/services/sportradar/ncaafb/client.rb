require "net/http"
require "json"

module Sportradar
  module Ncaafb
    # Thin client for the Sportradar NCAA Football v7 API.
    # https://developer.sportradar.com/football/docs/ncaafb-ig-api-basics
    class Client
      class Error < StandardError
        attr_reader :status

        def initialize(message, status: nil)
          super(message)
          @status = status
        end
      end

      class ConfigurationError < Error; end
      class RateLimitError < Error; end
      class NotFoundError < Error; end

      BASE_URL = "https://api.sportradar.com/ncaafb".freeze
      VERSION = "v7".freeze
      SEASON_TYPES = %w[PRE REG PST].freeze

      # Responses are cached so repeated requests never hit the API (and its
      # rate limit) when we already hold the data. Data that can no longer
      # change is kept for a long time; live data is kept briefly.
      TTL_STATIC = 1.day
      TTL_FINAL = 30.days
      TTL_LIVE = 1.minute
      TTL_CURRENT_SCHEDULE = 10.minutes

      def initialize(api_key: ENV["SPORTRADAR_API_KEY"],
                     access_level: ENV.fetch("SPORTRADAR_ACCESS_LEVEL", "trial"),
                     language: "en",
                     cache: Rails.cache,
                     open_timeout: 5,
                     read_timeout: 10)
        @api_key = api_key
        @access_level = access_level
        @language = language
        @cache = cache
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def league_hierarchy
        get("league/hierarchy", ttl: TTL_STATIC)
      end

      def season_schedule(year, season_type = "REG")
        get("games/#{Integer(year)}/#{validate_season_type(season_type)}/schedule", ttl: schedule_ttl(year))
      end

      def weekly_schedule(year, season_type, week)
        get("games/#{Integer(year)}/#{validate_season_type(season_type)}/#{Integer(week)}/schedule", ttl: schedule_ttl(year))
      end

      # Sportradar has no per-team schedule feed, so this filters each season
      # schedule down to the team's games. Regular season and postseason are
      # both included by default; an unscheduled postseason (404) is skipped.
      def team_games(year, team_id = Teams::UTAH[:id], season_types: %w[REG PST])
        Array(season_types).flat_map do |type|
          schedule = season_schedule(year, type)
          games = Array(schedule["weeks"]).flat_map do |week|
            Array(week["games"]).map do |game|
              game.merge("week" => week["title"] || week["sequence"] || week["number"], "season_type" => type.to_s.upcase)
            end
          end
          games.select { |game| game.dig("home", "id") == team_id || game.dig("away", "id") == team_id }
        rescue NotFoundError
          raise unless type.to_s.upcase == "PST"

          []
        end
      end

      def game_summary(game_id)
        get("games/#{segment(game_id)}/summary", ttl: ->(data) { game_ttl(data) })
      end

      def game_boxscore(game_id)
        get("games/#{segment(game_id)}/boxscore", ttl: ->(data) { game_ttl(data) })
      end

      # Every play of the game in order (periods -> events), enough to rebuild it.
      def game_play_by_play(game_id)
        get("games/#{segment(game_id)}/pbp", ttl: ->(data) { game_ttl(data) })
      end

      # Team and player statistics for the game.
      def game_statistics(game_id)
        get("games/#{segment(game_id)}/statistics", ttl: ->(data) { game_ttl(data) })
      end

      def team_profile(team_id = Teams::UTAH[:id])
        get("teams/#{segment(team_id)}/profile", ttl: TTL_STATIC)
      end

      def team_roster(team_id = Teams::UTAH[:id])
        get("teams/#{segment(team_id)}/full_roster", ttl: TTL_STATIC)
      end

      # +ttl+ is a duration, or a callable that receives the parsed response.
      def get(path, ttl: TTL_STATIC)
        raise ConfigurationError, "SPORTRADAR_API_KEY is not set" if @api_key.blank?

        key = [ "sportradar/ncaafb", @access_level, path ]
        cached = @cache.read(key)
        return cached unless cached.nil?

        data = request(path)
        @cache.write(key, data, expires_in: ttl.respond_to?(:call) ? ttl.call(data) : ttl)
        data
      end

      private

      def request(path)
        uri = URI("#{BASE_URL}/#{@access_level}/#{VERSION}/#{@language}/#{path}.json")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        req = Net::HTTP::Get.new(uri)
        req["x-api-key"] = @api_key
        req["Accept"] = "application/json"

        handle(http.request(req))
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise Error, "Sportradar request failed: #{e.class}"
      end

      def handle(response)
        status = response.code.to_i
        case status
        when 200..299 then JSON.parse(response.body)
        when 404 then raise NotFoundError.new("Not found", status: status)
        when 429 then raise RateLimitError.new("Rate limit exceeded", status: status)
        else raise Error.new("Sportradar API returned HTTP #{status}", status: status)
        end
      end

      # Past seasons are final. College seasons run Aug-Jan, so Jan-Feb
      # still belongs to the previous year's season.
      def schedule_ttl(year)
        today = Time.current
        current_season = today.month >= 3 ? today.year : today.year - 1
        Integer(year) < current_season ? TTL_FINAL : TTL_CURRENT_SCHEDULE
      end

      def game_ttl(data)
        data["status"] == "closed" ? TTL_FINAL : TTL_LIVE
      end

      def validate_season_type(type)
        type = type.to_s.upcase
        raise ArgumentError, "season type must be one of #{SEASON_TYPES.join(', ')}" unless SEASON_TYPES.include?(type)

        type
      end

      # Guards against path injection through IDs.
      def segment(value)
        value = value.to_s
        raise ArgumentError, "invalid id" unless value.match?(/\A[\w-]+\z/)

        value
      end
    end
  end
end
