class ServerSnapshot < ApplicationRecord
  RETENTION = 1.week

  belongs_to :server

  def self.prune
    where(checked_at: ...RETENTION.ago).delete_all
  end
end
