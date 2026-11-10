class SchedulesController < ApplicationController
  def show
    @team = Sportradar::Ncaafb::Teams::UTAH
    @season = params[:season].presence || current_season.to_s

    unless @season.is_a?(String) && @season.match?(/\A\d{4}\z/)
      @season = ""
      @error = "Enter a four-digit season year."
      return
    end

    @games = Sportradar::Ncaafb::Client.new.team_games(@season)
    @games = @games.sort_by { |game| [ game_date(game).nil? ? 1 : 0, game_date(game) || Time.at(0) ] }
  rescue Sportradar::Ncaafb::Client::ConfigurationError
    @error = "The Sportradar API key is not configured. Set SPORTRADAR_API_KEY and restart the app."
  rescue Sportradar::Ncaafb::Client::RateLimitError
    @error = "Sportradar's request limit was reached. Please wait a moment and try again."
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
