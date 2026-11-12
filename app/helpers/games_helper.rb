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
    reason = drive["end_reason"].to_s.strip
    return reason if reason.present? && reason.casecmp("unknown") != 0

    plays = (drive["events"] || []).select do |event|
      event["type"] == "play" && event["play_type"] != "kickoff" && !event["description"].to_s.match?(/\bno play\b/i)
    end
    last_play = plays.last
    if last_play && %w[extra_point two_point_conversion].include?(last_play["play_type"])
      previous_play = plays[-2]
      return "Inferred: Touchdown" if previous_play && touchdown?(previous_play) && possession_retained?(previous_play)
      return "Inferred: Extra point attempt" if last_play["play_type"] == "extra_point"
      return "Inferred: Two-point conversion attempt"
    end

    inferred = infer_play_result(last_play) if last_play
    return "Inferred: #{inferred}" if inferred

    next_drive = (next_period&.dig("pbp") || []).find { |entry| entry["type"] == "drive" }
    if drive["id"].present? && next_drive && next_drive["id"] == drive["id"]
      return "Continued in next period"
    end

    following_entries.each do |entry|
      break if %w[drive play].include?(entry["type"])
      next unless entry["event_type"] == "period_end"

      return entry["description"].presence || "End of period"
    end

    "Result unavailable"
  end

  def infer_play_result(play)
    categories = (play["details"] || []).map { |detail| detail["category"] }
    changed = possession_changed?(play)
    return "Interception" if categories.any? { |category| category.to_s.include?("interception") } && changed
    return "Fumble lost" if categories.include?("fumble") && changed
    return "Touchdown" if touchdown?(play) && possession_retained?(play)

    case play["play_type"]
    when "punt" then return "Punt" if changed
    when "field_goal"
      stat = (play["statistics"] || []).find { |item| item["stat_type"] == "field_goal" }
      return "Field goal made" if stat && stat["made"] == 1
      return "Field goal blocked" if stat && stat["blocked"] == 1
      return "Field goal missed" if stat && stat["missed"] == 1
      return "Field goal attempt"
    end

    return "Turnover on downs" if changed && play.dig("start_situation", "down") == 4
    return "Change of possession" if changed

    nil
  end

  def touchdown?(play)
    (play["details"] || []).any? { |detail| detail["category"] == "touchdown" }
  end

  def possession_changed?(play)
    start_id = play.dig("start_situation", "possession", "id")
    end_id = play.dig("end_situation", "possession", "id")
    start_id.present? && end_id.present? && start_id != end_id
  end

  def possession_retained?(play)
    start_id = play.dig("start_situation", "possession", "id")
    end_id = play.dig("end_situation", "possession", "id")
    start_id.present? && start_id == end_id
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
