module AppsHelper
  def health_badge(snapshot)
    label, modifier =
      if snapshot.nil? then [ "Not checked yet", "unknown" ]
      elsif snapshot.healthy? then [ "Healthy", "up" ]
      elsif snapshot.stopped? then [ "Stopped", "stopped" ]
      elsif snapshot.running_unchecked? then [ "Running · not health-checked", "unknown" ]
      else [ "Down", "down" ]
      end
    tag.span(label, class: "health health--#{modifier}", title: ("He's Gone" if modifier == "down"))
  end

  # "HEAD abc1234 · 2 commits ahead of running · uncommitted changes"
  def ship_preview_line(preview)
    return tag.p("Can't read the repo's HEAD", class: "ship-preview ship-preview--warn") unless preview.readable?

    head = [ "HEAD ", tag.span(preview.head_short_sha, class: "mono") ]
    head << tag.span(preview.branch ? " on #{preview.branch}" : " detached", class: "ship-preview__warn") unless preview.main_branch?
    parts = [ safe_join(head),
              safe_join([ ship_position(preview), running_age(preview) ].compact) ]
    parts << tag.span("uncommitted changes", class: "ship-preview__warn") if preview.uncommitted_changes?
    parts << ci_label(preview.ci_state)
    tag.p(safe_join(parts, " · "), class: "ship-preview")
  end

  def deploy_confirm(app, preview)
    lines = [ "Deploy #{app.name} to #{app.server.name}?" ]
    lines << (preview.readable? ? "Kamal will build #{preview.head_short_sha} from #{app.repo_path}." : "Can't read HEAD in #{app.repo_path}.")
    lines << "Warning: #{branch_warning(preview)}" if preview.readable? && !preview.main_branch?
    lines << "Warning: HEAD is #{pluralize(preview.behind, "commit")} behind the running version, so this deploy takes them off the server." if preview.behind.to_i > 0
    lines << "Warning: Uncommitted changes won't be included." if preview.uncommitted_changes?
    ci_warning(preview)&.then { lines << "Warning: #{it}" }
    lines.join("\n\n")
  end

  private

  def ci_label(state)
    case state
    when :passed then "CI passed"
    when :failed then tag.span("CI failed", class: "ship-preview__warn")
    when :missing then tag.span("CI not passed", class: "ship-preview__warn")
    when :unknown then tag.span("CI status unknown", class: "ship-preview__warn")
    when :unchecked then tag.span("CI not checked", class: "muted")
    else tag.span("no local CI", class: "muted")
    end
  end

  def ci_warning(preview)
    case preview.ci_state
    when :failed then "Local CI failed on #{preview.head_short_sha}."
    when :missing then "Local CI hasn't signed off on #{preview.head_short_sha} (not pushed, or CI not run)."
    when :unknown then "Couldn't check whether local CI passed."
    end
  end

  def branch_warning(preview)
    preview.branch ? "HEAD is on branch #{preview.branch}, not main or master." : "HEAD is detached, not on main or master."
  end

  def running_age(preview)
    " (as of #{exact_time(preview.running_seen_at)})" if preview.running_seen_at
  end

  def ship_position(preview)
    ahead, behind = preview.ahead, preview.behind
    if ahead.nil? then "running version unknown"
    elsif ahead.zero? && behind.zero? then "same as running"
    elsif behind.zero? then "#{pluralize(ahead, "commit")} ahead of running"
    elsif ahead.zero? then tag.span("#{pluralize(behind, "commit")} behind running", class: "ship-preview__warn")
    else tag.span("#{ahead} ahead, #{behind} behind running", class: "ship-preview__warn")
    end
  end
end
