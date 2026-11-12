module ApplicationHelper
  def game_status_label(status)
    return "FINAL" if status == "closed"

    status.presence&.tr("_-", " ")&.upcase || "STATUS TBD"
  end
end
