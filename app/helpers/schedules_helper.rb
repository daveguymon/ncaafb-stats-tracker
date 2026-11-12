module SchedulesHelper
  def schedule_record(record)
    return "Record unavailable" unless record

    values = [ record[:wins], record[:losses] ]
    values << record[:ties] if record[:ties].positive?
    values.join("-")
  end
end
