module Sportradar
  module Ncaafb
    class DriveTeam
      def self.call(drive, summary)
        team = resolve(drive["offensive_team"], summary)
        return team if team

        play = (drive["events"] || []).find do |event|
          event["type"] == "play" && event["play_type"] != "kickoff" && event.dig("start_situation", "possession").present?
        end
        resolve(play&.dig("start_situation", "possession"), summary)
      end

      def self.resolve(team, summary)
        return unless team.is_a?(Hash)

        if team["id"].present?
          known_team = [ summary["home"], summary["away"] ].compact.find { |candidate| candidate["id"] == team["id"] }
          team = known_team if known_team
        end

        return if team.values_at("market", "name", "alias").all?(&:blank?)

        team
      end
      private_class_method :resolve
    end
  end
end
