require "singleton"

class CommunityPetStore
  include Singleton

  class CustomizationError < StandardError; end

  def current
    synchronize { enrich_state(read_state) }
  end

  def apply_profile(profile)
    synchronize do
      state = CommunityPetBuilder.new(state: read_state).apply_profile(profile)
      write_state(state)
      enrich_state(state)
    end
  end

  def update_customization(caretaker_username:, title: nil, name: nil, outfit: nil)
    synchronize do
      state = enrich_state(read_state)
      top_caretaker = state[:top_caretaker]

      # Playful MVP authority: the frontend sends the current leaderboard username.
      # This is intentionally not secure account ownership and should not be treated as auth.
      unless top_caretaker && same_username?(top_caretaker[:username], caretaker_username)
        raise CustomizationError, "Only the current Top Caretaker can customize the Community Pushpet"
      end

      next_state = state.merge(
        display_title: clean_value(title, fallback: state[:display_title] || state[:title], max_length: 40),
        featured_name: clean_value(name, fallback: state[:featured_name] || state[:name], max_length: 28),
        outfit: allowed_outfit(outfit, state),
        history: customization_feed(state, caretaker_username),
        updated_at: Time.current.iso8601
      )

      next_state[:feed_log] = next_state[:history]
      write_state(next_state)
      enrich_state(next_state)
    end
  end

  private

  def synchronize(&block)
    mutex.synchronize(&block)
  end

  def read_state
    normalize_state(CommunityPetState.global.state.deep_symbolize_keys)
  rescue ActiveRecord::ActiveRecordError
    fresh_default_state
  end

  def write_state(state)
    CommunityPetState.global.update!(state: state.deep_stringify_keys)
  end

  def same_username?(left, right)
    left.to_s.casecmp?(right.to_s.strip)
  end

  def allowed_outfit(outfit, state)
    requested = outfit.to_s.strip
    return state[:outfit] if requested.blank?

    allowed_ids = state.fetch(:unlocked_outfits, []).map { |entry| entry.fetch(:id).to_s }
    allowed_ids << "caretaker_crown"
    allowed_ids << "none"
    allowed_ids.include?(requested) ? requested : state[:outfit]
  end

  def clean_value(value, fallback:, max_length:)
    cleaned = value.to_s.strip
    return fallback if cleaned.blank?

    cleaned.first(max_length)
  end

  def customization_feed(state, caretaker_username)
    [
      {
        type: "customization",
        label: "#{caretaker_username} customized the Community Pushpet",
        timestamp: Time.current.iso8601
      },
      *state.fetch(:history, state.fetch(:feed, []))
    ].first(20)
  end

  def fresh_default_state
    state = CommunityPetBuilder.default_state
    state[:feed_log] = state[:history]
    state
  end

  def normalize_state(state)
    return fresh_default_state unless state[:state_version] == CommunityPetBuilder.default_state[:state_version]

    default_state = fresh_default_state
    normalized = default_state.merge(state)
    normalized[:featured_name] ||= state[:name] || default_state[:featured_name]
    normalized[:display_title] ||= state[:title] || default_state[:display_title]
    normalized[:history] = state[:history] || state[:feed] || default_state[:history]
    normalized[:feed_log] = normalized[:history]
    normalized[:contributors] = normalized.fetch(:contributors, {}).to_h { |key, value| [key.to_s, value] }
    normalized
  end

  def enrich_state(state)
    leaderboard = LeaderboardEntry.top.map(&:as_api).map(&:deep_symbolize_keys)
    return state if leaderboard.empty?

    state.merge(
      leaderboard: leaderboard,
      top_caretaker: leaderboard.first
    )
  rescue ActiveRecord::ActiveRecordError
    state
  end

  def mutex
    @mutex ||= Mutex.new
  end
end
