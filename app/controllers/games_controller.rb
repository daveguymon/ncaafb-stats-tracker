class GamesController < ApplicationController
  def show
    @season = params[:season] if params[:season].is_a?(String) && params[:season].match?(/\A\d{4}\z/)
    @game = Sportradar::Ncaafb::Client.new.game_play_by_play(params[:id])
    @periods = @game["periods"] || []
  rescue ArgumentError
    @error = "Invalid game ID."
  rescue Sportradar::Ncaafb::Client::ConfigurationError
    @error = "The Sportradar API key is not configured. Set SPORTRADAR_API_KEY and restart the app."
  rescue Sportradar::Ncaafb::Client::NotFoundError
    @error = "Play-by-play data for this game was not found."
  rescue Sportradar::Ncaafb::Client::RateLimitError
    @error = "Sportradar's request limit was reached. Try again later or check your account quota."
  rescue Sportradar::Ncaafb::Client::Error, JSON::ParserError => error
    Rails.logger.error("Play-by-play request failed: #{error.class}: #{error.message}")
    @error = "Could not load play-by-play data from Sportradar. Please try again."
  end
end
