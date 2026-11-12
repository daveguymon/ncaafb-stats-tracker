class SportradarController < ApplicationController
  # Handlers are matched last-to-first, so the generic error goes first.
  rescue_from Sportradar::Ncaafb::Client::Error do |error|
    Rails.logger.error("Sportradar request failed: #{error.class}: #{error.message}")
    render json: { error: "Upstream Sportradar error" }, status: :bad_gateway
  end
  rescue_from Sportradar::Ncaafb::Client::ConfigurationError do |error|
    Rails.logger.error("Sportradar configuration error: #{error.message}")
    render json: { error: "Sportradar API is not configured" }, status: :service_unavailable
  end
  rescue_from Sportradar::Ncaafb::Client::NotFoundError do
    render json: { error: "Not found" }, status: :not_found
  end
  rescue_from Sportradar::Ncaafb::Client::RateLimitError do
    render json: { error: "Sportradar request limit reached. Try again later or check your account quota." }, status: :too_many_requests
  end
  rescue_from ArgumentError do
    render json: { error: "Invalid parameter" }, status: :bad_request
  end

  def hierarchy
    render json: client.league_hierarchy
  end

  def schedule
    render json: client.season_schedule(params[:year], params[:season_type])
  end

  def utah_games
    render json: client.team_games(params[:year])
  end

  def game
    render json: client.game_summary(params[:id])
  end

  def play_by_play
    render json: client.game_play_by_play(params[:id])
  end

  def game_statistics
    render json: client.game_statistics(params[:id])
  end

  private

  def client
    Sportradar::Ncaafb::Client.new
  end
end
