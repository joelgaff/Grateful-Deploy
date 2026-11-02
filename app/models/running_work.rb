# What a restart of Grateful Deploy would cut off: deploys still queued or
# running, and log sessions still streaming. bin/release refuses while any.
module RunningWork
  def self.describe
    parts = [
      named("deploy", Deploy.in_flight.includes(:app)),
      named("log session", LogSession.running.includes(:app))
    ].compact
    return if parts.empty?

    count = Deploy.in_flight.count + LogSession.running.count
    "#{parts.to_sentence} #{count == 1 ? "is" : "are"} running"
  end

  def self.named(noun, records)
    return if records.empty?

    "#{records.size} #{noun.pluralize(records.size)} (#{records.map { it.app.name }.sort.join(", ")})"
  end
  private_class_method :named
end
