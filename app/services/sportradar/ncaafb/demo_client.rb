require "json"

module Sportradar
  module Ncaafb
    class DemoClient
      SEASON = "2024".freeze
      GAME_ID = "demo-utah-sample-state".freeze

      def request_metadata
        []
      end

      def season_schedule(year, season_type = "REG")
        raise ArgumentError, "Invalid season" unless year.to_s.match?(/\A\d{4}\z/)

        type = season_type.to_s.upcase
        raise ArgumentError, "Invalid season type" unless Client::SEASON_TYPES.include?(type)
        raise Client::NotFoundError, "Demo season not found" unless year.to_s == SEASON && %w[REG PST].include?(type)

        type == "REG" ? read_fixture("schedule") : { "weeks" => [] }
      end

      def season_games(year, season_types: %w[REG PST], allow_partial: false)
        Array(season_types).flat_map do |type|
          ScheduleGames.flatten(season_schedule(year, type), type)
        end
      end

      def team_games(year, team_id = Teams::UTAH[:id], season_types: %w[REG PST])
        season_games(year, season_types: season_types).select do |game|
          [ game.dig("home", "id"), game.dig("away", "id") ].include?(team_id)
        end
      end

      def game_play_by_play(game_id)
        raise Client::NotFoundError, "Demo game not found" unless game_id == GAME_ID

        read_fixture("play_by_play")
      end

      def game_summary(_game_id)
        raise Client::NotFoundError, "Demo summary not available"
      end

      def league_hierarchy
        raise Client::NotFoundError, "Demo hierarchy not available"
      end

      def game_statistics(_game_id)
        raise Client::NotFoundError, "Demo statistics not available"
      end

      private

      def read_fixture(name)
        JSON.parse(Rails.root.join("db/demo/#{name}.json").read)
      rescue SystemCallError, JSON::ParserError => error
        raise Client::Error, "Demo data could not be read: #{error.class}"
      end
    end
  end
end
