class Current < ActiveSupport::CurrentAttributes
  # Single-tenant today; repoint resolution when multi-tenancy activates.
  attribute :organization
  attribute :user
end
