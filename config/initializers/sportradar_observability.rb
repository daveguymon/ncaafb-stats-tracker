ActiveSupport::Notifications.subscribe(/\Asportradar\./) do |name, start, finish, _id, payload|
  event = {
    event: name,
    duration_ms: ((finish - start) * 1000).round(1),
    outcome: payload[:outcome],
    kind: payload[:kind],
    status: payload[:status],
    error_class: payload[:error_class] || payload[:exception]&.first
  }.compact
  Rails.logger.info(event.to_json)
end
