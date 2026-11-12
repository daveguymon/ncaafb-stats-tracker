module SchedulesHelper
  def schedule_record(record, coverage: :complete)
    return "Record unavailable" unless record

    values = [ record[:wins], record[:losses] ]
    values << record[:ties] if record[:ties].positive?
    label = values.join("-")
    coverage == :unverified ? "#{label} (coverage unverified)" : label
  end
end
