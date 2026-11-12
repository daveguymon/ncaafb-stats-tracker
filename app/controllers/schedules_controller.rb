class SchedulesController < ApplicationController
  def show
    @team = Sportradar::Ncaafb::Teams::UTAH
    @season = params[:season].presence || current_season.to_s

    unless @season.is_a?(String) && @season.match?(/\A\d{4}\z/)
      @season = ""
      @error = "Enter a four-digit season year."
      return
    end

    client = Sportradar::Ncaafb::Client.new
    season_games = client.season_games(@season)
    @freshness = client.request_metadata
    @games = season_games.select { |game| [ game.dig("home", "id"), game.dig("away", "id") ].include?(@team[:id]) }
    @games = @games.sort_by { |game| [ game_date(game).nil? ? 1 : 0, game_date(game) || Time.at(0) ] }
    @records = Sportradar::Ncaafb::SeasonRecords.new(season_games).for_games(@games)
  rescue Sportradar::Ncaafb::Client::ConfigurationError => error
    Rails.logger.error("Sportradar configuration error: #{error.message}")
    @error = "Sportradar is not configured correctly. Check the API key and quota settings."
  rescue Sportradar::Ncaafb::Client::RateLimitError
    @error = "Sportradar's request limit was reached. Try again later or check your account quota."
  rescue Sportradar::Ncaafb::Client::NotFoundError
    @error = "The regular-season schedule for #{@season} was not found."
  rescue Sportradar::Ncaafb::Client::Error, JSON::ParserError => error
    Rails.logger.error("Schedule request failed: #{error.class}: #{error.message}")
    @error = "Could not load the schedule from Sportradar. Please try again."
  end

  private

  def current_season
    today = Time.current
    today.month >= 3 ? today.year : today.year - 1
  end

  def game_date(game)
    return if game["scheduled"].blank?

    Time.iso8601(game["scheduled"])
  rescue ArgumentError
    nil
  end
  helper_method :game_date
end
