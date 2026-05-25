class LeaderboardEntry < ApplicationRecord
  before_validation :normalize_username

  validates :username, presence: true, uniqueness: { case_sensitive: false }

  def self.record!(profile:, pushpet:)
    entry = find_or_initialize_by_username(profile.fetch(:username))
    entry.username = profile.fetch(:username)
    entry.score = [entry.score.to_i, profile.fetch(:pet_score, 0).to_i].max
    entry.searches = entry.searches.to_i + 1
    entry.avatar_url = profile[:avatar_url]
    entry.mood = profile[:mood]
    entry.dormancy_state = profile[:dormancy_state]
    entry.species = pushpet&.species || entry.species || "goat_dragon"
    entry.color = pushpet&.color || entry.color || "blue"
    entry.accessory = pushpet&.accessory || entry.accessory || "none"
    entry.equipped_accessories = pushpet&.equipped_accessories || entry.equipped_accessories || {}
    entry.last_seen_at = Time.current
    entry.save!
    entry
  end

  def self.find_or_initialize_by_username(username)
    where("lower(username) = ?", username.to_s.strip.downcase).first || new(username: username.to_s.strip)
  end

  def self.top(limit = 10)
    order(score: :desc, username: :asc).limit(limit)
  end

  def as_api
    {
      username: username,
      searches: searches,
      score: score,
      avatar_url: avatar_url,
      mood: mood,
      dormancy_state: dormancy_state,
      species: species,
      color: color,
      accessory: accessory,
      equipped: equipped_accessories.to_h,
      last_seen_at: last_seen_at&.iso8601
    }
  end

  private

  def normalize_username
    self.username = username.to_s.strip
  end
end
