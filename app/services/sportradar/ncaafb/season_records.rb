module Sportradar
  module Ncaafb
    class SeasonRecords
      FINAL_STATUSES = %w[complete closed].freeze
      PLAYED_STATUSES = (FINAL_STATUSES + %w[inprogress halftime]).freeze

      def initialize(games)
        @games_by_team = Hash.new { |hash, key| hash[key] = [] }
        games.each do |game|
          [ game.dig("home", "id"), game.dig("away", "id") ].compact.uniq.each do |id|
            @games_by_team[id] << game
          end
        end
      end

      def for_games(games)
        games.to_h do |game|
          [ game.object_id, {
            "away" => record_before(game, "away"),
            "home" => record_before(game, "home")
          } ]
        end
      end

      private

      def record_before(game, side)
        team = game[side] || {}
        team_id = team["id"]
        cutoff = scheduled_at(game)
        return if team_id.blank? || cutoff.nil?

        # A time-TBD kickoff may use a placeholder time, so only count results
        # from earlier dates, not games on the same day.
        cutoff = cutoff.utc.beginning_of_day if game["status"] == "time-tbd"
        counts = { wins: 0, losses: 0, ties: 0 }

        @games_by_team[team_id].each do |other|
          next if other.equal?(game) || !FINAL_STATUSES.include?(other["status"])

          date = scheduled_at(other)
          return if date.nil?
          if game["status"] == "time-tbd" && date.utc.to_date == cutoff.to_date
            return
          end
          next if date >= cutoff

          home_score = other.dig("scoring", "home_points")
          away_score = other.dig("scoring", "away_points")
          return unless home_score.is_a?(Numeric) && away_score.is_a?(Numeric)

          team_score, opponent_score = other.dig("home", "id") == team_id ? [ home_score, away_score ] : [ away_score, home_score ]
          result = team_score == opponent_score ? :ties : (team_score > opponent_score ? :wins : :losses)
          counts[result] += 1
        end

        # A played regular-season game's sequence can reveal missing results in
        # the schedule feed. Future games may have unplayed games ahead of them.
        game_number = team["game_number"]
        if game["season_type"] == "REG" && PLAYED_STATUSES.include?(game["status"]) &&
            game_number.is_a?(Integer) && game_number.positive? &&
            counts.values.sum != game_number - 1
          return
        end

        counts
      end

      def scheduled_at(game)
        Time.iso8601(game["scheduled"]) if game["scheduled"].present?
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
