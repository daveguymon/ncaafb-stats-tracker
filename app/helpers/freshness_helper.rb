module FreshnessHelper
  def freshness_label(entry)
    path = entry[:path]
    return "Regular season" if path.match?(%r{/REG/schedule\z})
    return "Postseason" if path.match?(%r{/PST/schedule\z})
    return "Play-by-play" if path.end_with?("/pbp")

    "Sportradar feed"
  end

  def freshness_description(entry)
    return "Feed unavailable (not found); no postseason data included." if entry[:source] == :not_found

    source = entry[:source] == :cached ? "Cached" : "Fetched from Sportradar"
    return "#{source}; fetch time unavailable" unless entry[:fetched_at]

    "#{source}; fetched #{entry[:fetched_at].utc.strftime('%b %d, %Y at %H:%M:%S UTC')}"
  end
end
