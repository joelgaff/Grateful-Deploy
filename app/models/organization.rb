class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :servers, dependent: :destroy
  has_many :apps, through: :servers
  validates :name, presence: true
end
