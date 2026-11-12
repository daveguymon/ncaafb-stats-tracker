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
    return Sportradar::Ncaafb::DemoClient.new if demo_mode?

    visitor_key = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, request.remote_ip)
    Sportradar::Ncaafb::Client.new(visitor_key: visitor_key)
  end
end
