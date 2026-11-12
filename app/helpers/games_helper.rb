module GamesHelper
  def game_team_name(team)
    return "Team TBD" if team.blank?

    [ team["market"], team["name"] ].compact_blank.join(" ").presence || team["alias"].presence || "Team TBD"
  end

  def drive_team_name(drive, summary)
    team_name = resolve_drive_team(drive["offensive_team"], summary)
    return team_name if team_name

    play = (drive["events"] || []).find do |event|
      event["type"] == "play" && event["play_type"] != "kickoff" && event.dig("start_situation", "possession").present?
    end
    resolve_drive_team(play&.dig("start_situation", "possession"), summary) || "Team TBD"
  end

  def resolve_drive_team(team, summary)
    return unless team.is_a?(Hash)

    if team["id"].present?
      known_team = [ summary["home"], summary["away"] ].compact.find { |candidate| candidate["id"] == team["id"] }
      team = known_team if known_team
    end

    return if team.values_at("market", "name", "alias").all?(&:blank?)

    game_team_name(team)
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
