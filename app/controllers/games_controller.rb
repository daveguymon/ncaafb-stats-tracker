class GamesController < ApplicationController
  def show
    @season = params[:season] if params[:season].is_a?(String) && params[:season].match?(/\A\d{4}\z/)
    client = data_client
    @game = client.game_play_by_play(params[:id])
    @freshness = client.request_metadata
    @periods = @game["periods"] || []
  rescue ArgumentError
    @error = "Invalid game ID."
  rescue Sportradar::Ncaafb::Client::ConfigurationError => error
    Rails.logger.error("Sportradar configuration error: #{error.message}")
    @error = "Sportradar is not configured correctly. Check the API key and quota settings."
  rescue Sportradar::Ncaafb::Client::NotFoundError
    @error = demo_mode? ? "This game is not available in the demo." : "Play-by-play data for this game was not found."
  rescue Sportradar::Ncaafb::Client::RateLimitError
    @error = "Sportradar's request limit was reached. Try again later or check your account quota."
  rescue Sportradar::Ncaafb::Client::Error, JSON::ParserError => error
    Rails.logger.error("Play-by-play request failed: #{error.class}: #{error.message}")
    @error = demo_mode? ? "Could not load the demo play-by-play. Please contact the app operator." : "Could not load play-by-play data from Sportradar. Please try again."
  end
end
