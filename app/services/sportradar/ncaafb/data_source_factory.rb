module Sportradar
  module Ncaafb
    class DataSourceFactory
      def initialize(live_builder: ->(visitor_key:) { Client.new(visitor_key: visitor_key) },
                     demo_builder: -> { DemoClient.new })
        @live_builder = live_builder
        @demo_builder = demo_builder
      end

      def build(demo:, remote_ip:)
        return @demo_builder.call if demo

        visitor_key = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, remote_ip)
        @live_builder.call(visitor_key: visitor_key)
      end
    end
  end
end
