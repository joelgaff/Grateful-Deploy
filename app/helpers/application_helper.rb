module ApplicationHelper
  # "Oct 15, 16:42", in the laptop's time zone. Used instead of "N minutes ago",
  # which goes stale on a page that isn't re-rendered.
  def exact_time(time)
    l(time, format: :exact)
  end
end
