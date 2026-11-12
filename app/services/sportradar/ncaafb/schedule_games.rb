module Sportradar
  module Ncaafb
    module ScheduleGames
      def self.flatten(schedule, season_type)
        Array(schedule["weeks"]).flat_map do |week|
          Array(week["games"]).map do |game|
            game.merge("week" => week["title"] || week["sequence"] || week["number"],
              "season_type" => season_type.to_s.upcase)
          end
        end
      end
    end
  end
end
