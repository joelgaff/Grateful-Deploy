# Makes every Turbo broadcast raise for the block, like a busy database
# during a page redraw would.
module FailingBroadcasts
  METHODS = %i[broadcast_replace_to broadcast_append_to].freeze

  def with_failing_broadcasts
    METHODS.each do |name|
      Turbo::StreamsChannel.define_singleton_method(name) { |*, **| raise ActiveRecord::StatementTimeout, "database is locked" }
    end
    yield
  ensure
    METHODS.each { Turbo::StreamsChannel.singleton_class.remove_method(it) }
  end
end
