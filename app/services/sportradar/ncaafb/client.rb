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

      def initialize(api_key: ENV["SPORTRADAR_API_KEY"],
                     access_level: ENV.fetch("SPORTRADAR_ACCESS_LEVEL", "trial"),
                     language: "en",
                     cache: Rails.cache,
                     cache_ttl: 5.minutes,
                     open_timeout: 5,
                     read_timeout: 10)
        @api_key = api_key
        @access_level = access_level
        @language = language
        @cache = cache
        @cache_ttl = cache_ttl
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def league_hierarchy
        get("league/hierarchy")
      end

      def season_schedule(year, season_type = "REG")
        get("games/#{year}/#{validate_season_type(season_type)}/schedule")
      end

      def weekly_schedule(year, season_type, week)
        get("games/#{year}/#{validate_season_type(season_type)}/#{Integer(week)}/schedule")
      end

      def game_summary(game_id)
        get("games/#{segment(game_id)}/summary")
      end

      def game_boxscore(game_id)
        get("games/#{segment(game_id)}/boxscore")
      end

      def team_profile(team_id)
        get("teams/#{segment(team_id)}/profile")
      end

      def team_roster(team_id)
        get("teams/#{segment(team_id)}/full_roster")
      end

      def get(path)
        raise ConfigurationError, "SPORTRADAR_API_KEY is not set" if @api_key.blank?

        @cache.fetch([ "sportradar/ncaafb", @access_level, path ], expires_in: @cache_ttl) do
          request(path)
        end
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
