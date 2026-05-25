require "singleton"
require "active_record"

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

  def update_customization(caretaker_username:, title: nil, name: nil, species: nil, color: nil, outfit: nil, environment: nil)
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
        species: allowed_species(species, state),
        color: allowed_color(color, state),
        outfit: allowed_outfit(outfit, state),
        environment: allowed_environment(environment, state),
        customized_fields: customized_fields_for(state, title: title, name: name, species: species, color: color, outfit: outfit, environment: environment),
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

  def allowed_species(species, state)
    requested = species.to_s.strip
    fallback = state[:species] || CommunityPetBuilder::DEFAULT_SPECIES
    return fallback if requested.blank?

    %w[goat_dragon raccoon star_axolotl].include?(requested) ? requested : fallback
  end

  def allowed_color(color, state)
    requested = color.to_s.strip
    fallback = state[:color] || CommunityPetBuilder::DEFAULT_COLOR
    return fallback if requested.blank?

    %w[blue pink green purple orange white].include?(requested) ? requested : fallback
  end

  def allowed_environment(environment, state)
    requested = environment.to_s.strip
    fallback = state[:environment] || CommunityPetBuilder::DEFAULT_ENVIRONMENT
    return fallback if requested.blank?

    aliases = {
      "aqua" => "petplace1",
      "sunny" => "petplace2",
      "garden" => "petplace2",
      "night" => "petplace3"
    }
    normalized = aliases.fetch(requested, requested)

    %w[petplace1 petplace2 petplace3].include?(normalized) ? normalized : fallback
  end

  def clean_value(value, fallback:, max_length:)
    cleaned = value.to_s.strip
    return fallback if cleaned.blank?

    cleaned.first(max_length)
  end

  def customized_fields_for(state, title:, name:, species:, color:, outfit:, environment:)
    fields = state.fetch(:customized_fields, {}).deep_symbolize_keys
    fields[:display_title] = true if title.to_s.strip.present?
    fields[:featured_name] = true if name.to_s.strip.present?
    fields[:species] = true if species.to_s.strip.present?
    fields[:color] = true if color.to_s.strip.present?
    fields[:outfit] = true if outfit.to_s.strip.present?
    fields[:environment] = true if environment.to_s.strip.present?
    fields
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
    normalized[:species] = allowed_species(normalized[:species], default_state)
    normalized[:color] = allowed_color(normalized[:color], default_state)
    normalized[:environment] = allowed_environment(normalized[:environment], default_state)
    normalized[:evolution_stage] = default_state[:evolution_stage] if normalized[:community_score].to_i.zero? && normalized[:evolution_stage] == "hatchling"
    normalized[:mood] = default_state[:mood] if normalized[:community_score].to_i.zero? && normalized[:mood] == "cozy"
    normalized[:history] = state[:history] || state[:feed] || default_state[:history]
    normalized[:feed_log] = normalized[:history]
    normalized[:contributors] = normalized.fetch(:contributors, {}).to_h { |key, value| [key.to_s, value] }
    normalized[:customized_fields] = normalized.fetch(:customized_fields, {}).deep_symbolize_keys
    normalized
  end

  def enrich_state(state)
    leaderboard = LeaderboardEntry.top.map(&:as_api).map(&:deep_symbolize_keys)
    return state if leaderboard.empty?

    state.merge(
      leaderboard: leaderboard,
      top_caretaker: leaderboard.first
    )
  end

  def mutex
    @mutex ||= Mutex.new
  end
end
