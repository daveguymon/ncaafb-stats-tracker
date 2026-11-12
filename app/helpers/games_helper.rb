module GamesHelper
  def game_team_name(team)
    return "Team TBD" if team.blank?

    [ team["market"], team["name"] ].compact_blank.join(" ").presence || team["alias"].presence || "Team TBD"
  end

  def drive_team_name(drive, summary)
    game_team_name(Sportradar::Ncaafb::DriveTeam.call(drive, summary))
  end

  def drive_result(drive, following_entries, next_period)
    Sportradar::Ncaafb::DriveResult.call(drive, following_entries, next_period)
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
