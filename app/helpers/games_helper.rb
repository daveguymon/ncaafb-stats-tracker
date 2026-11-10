module GamesHelper
  def game_team_name(team)
    return "Team TBD" if team.blank?

    [ team["market"], team["name"] ].compact_blank.join(" ").presence || team["alias"].presence || "Team TBD"
  end

  def drive_team_name(team, summary)
    if team.is_a?(Hash) && team["id"].present?
      known_team = [ summary["home"], summary["away"] ].compact.find { |candidate| candidate["id"] == team["id"] }
      return game_team_name(known_team) if known_team
    end

    game_team_name(team)
  end

  def period_name(period, index)
    number = period["number"] || index + 1
    period["period_type"] == "overtime" ? "Overtime #{number}" : "Quarter #{number}"
  end

  def game_event_context(event)
    situation = event["start_situation"] || {}
    parts = []
    parts << "#{situation["down"]} & #{situation["yfd"]}" if situation["down"].to_i.positive? && !situation["yfd"].nil?
    location = situation["location"] || {}
    parts << [ location["alias"], location["yardline"] ].compact.join(" ") if location["yardline"]
    parts.join(" · ")
  end
end
