module ApplicationHelper
  # "Oct 15, 16:42", in the laptop's time zone. Used instead of "N minutes ago",
  # which goes stale on a page that isn't re-rendered.
  def exact_time(time)
    l(time, format: :exact)
  end

  # Each app's bear dances in its own colour, picked from its name so it never changes.
  BEAR_COLOURS = %w[#c8414b #d9822b #d8a62e #4f9a5a #3f6fb5].freeze

  def bear_palette(app)
    { b: BEAR_COLOURS[Zlib.crc32(app.name) % BEAR_COLOURS.size] }
  end
end
