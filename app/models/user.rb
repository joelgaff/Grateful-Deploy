class User < ApplicationRecord
  belongs_to :identity
  belongs_to :organization

  delegate :email, to: :identity
end
