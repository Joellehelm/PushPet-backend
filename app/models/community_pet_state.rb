class CommunityPetState < ApplicationRecord
  GLOBAL_KEY = "global"

  validates :key, presence: true, uniqueness: true

  def self.global
    find_or_create_by!(key: GLOBAL_KEY) do |record|
      record.state = CommunityPetBuilder.default_state
    end
  end
end
