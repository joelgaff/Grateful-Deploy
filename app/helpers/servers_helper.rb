module ServersHelper
  # A labelled usage bar, e.g. "RAM 3.47 GB of 7.56 GB (46%)". Pass text: to
  # describe the numbers differently (load average).
  def meter(label, used, total, modifier:, text: nil)
    return if used.nil? || total.to_i.zero?

    percent = [ (used * 100.0 / total).round, 100 ].min
    level = percent >= 90 ? "high" : percent >= 75 ? "warn" : "ok"
    text ||= "#{number_to_human_size(used)} of #{number_to_human_size(total)} (#{percent}%)"
    tag.div(class: "meter meter--#{modifier} meter--#{level}") do
      safe_join([
        tag.div(class: "meter__label") { safe_join([ tag.strong(label), " #{text}" ]) },
        tag.div(class: "meter__track") { tag.div(class: "meter__bar", style: "width: #{percent}%") }
      ])
    end
  end

  # 1-minute load against the number of CPUs: 4.0 on 4 CPUs is a full bar.
  def load_meter(snapshot)
    return unless snapshot.load_1 && snapshot.cpus

    averages = [ snapshot.load_1, snapshot.load_5, snapshot.load_15 ].map { format("%.2f", it) }.join(" · ")
    meter "Load", snapshot.load_1, snapshot.cpus, modifier: "load", text: "#{averages} on #{snapshot.cpus} CPUs"
  end
end
