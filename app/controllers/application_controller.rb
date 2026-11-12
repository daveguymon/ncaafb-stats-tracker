class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def demo_mode?
    ENV["DEMO_MODE"] == "true"
  end
  helper_method :demo_mode?

  def data_client
    demo_mode? ? Sportradar::Ncaafb::DemoClient.new : Sportradar::Ncaafb::Client.new
  end
end
