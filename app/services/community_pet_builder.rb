class CommunityPetBuilder
  DEFAULT_NAME = "Pushpet Prime"
  DEFAULT_TITLE = "Community Pushpet"
  DEFAULT_OUTFIT = "none"
  DEFAULT_ENVIRONMENT = "petplace1"
  CONTRIBUTION_DEDUPE_TTL = 10.minutes

  def self.default_state
    {
      state_version: 4,
      featured_name: DEFAULT_NAME,
      display_title: DEFAULT_TITLE,
      outfit: DEFAULT_OUTFIT,
      environment: DEFAULT_ENVIRONMENT,
      community_score: 0,
      level: 1,
      evolution_stage: "egg",
      mood: "idle",
      hunger: 45,
      happiness: 55,
      dominant_language: nil,
      top_caretaker: nil,
      contributors_count: 0,
      total_recent_pushes: 0,
      total_recent_prs: 0,
      active_users_count: 0,
      leaderboard: [],
      contributors: {},
      unlocked_outfits: [
        { id: "caretaker_crown", label: "Caretaker Crown", source_language: "Top Caretaker" }
      ],
      history: [
        {
          type: "community_hatch",
          label: "Community Pushpet is waiting for caretakers",
          timestamp: Time.current.iso8601
        }
      ],
      feed_log: [],
      updated_at: Time.current.iso8601
    }
  end

  def initialize(state:)
    @state = deep_symbolize(state)
    @state[:contributors] = stringify_contributors(@state.fetch(:contributors, {}))
  end

  def apply_profile(profile)
    profile = deep_symbolize(profile)
    username = profile.fetch(:username)
    skipped_duplicate = duplicate_contribution?(username)
    contributors = skipped_duplicate ? state.fetch(:contributors, {}) : update_contributors(profile)
    aggregates = aggregate(contributors)
    community_score = community_score_for(aggregates)
    leaderboard = update_leaderboard(username, profile.fetch(:pet_score, 0))
    top_caretaker = leaderboard.first
    outfits = merge_outfits(profile.fetch(:outfit_unlocks, []))
    dominant_language = aggregates[:dominant_language]

    next_state = state.merge(
      community_score: community_score,
      level: 1 + (community_score / 15).floor,
      evolution_stage: evolution_stage_for(community_score),
      hunger: community_hunger(community_score),
      happiness: community_happiness(community_score, aggregates[:active_users_count]),
      mood: community_mood(community_score, skipped_duplicate),
      dominant_language: dominant_language,
      outfit: outfit_for(dominant_language, outfits),
      top_caretaker: top_caretaker,
      contributors_count: contributors.length,
      total_recent_pushes: aggregates[:total_recent_pushes],
      total_recent_prs: aggregates[:total_recent_prs],
      active_users_count: aggregates[:active_users_count],
      leaderboard: leaderboard,
      contributors: contributors,
      unlocked_outfits: outfits,
      updated_at: Time.current.iso8601
    )

    history = update_feed(next_state, profile, skipped_duplicate)
    next_state.merge(history: history, feed_log: history)
  end

  private

  attr_reader :state

  def duplicate_contribution?(username)
    previous = state.fetch(:contributors, {})[contributor_key(username)]
    return false unless previous

    last_contributed_at = parse_time(previous[:last_contributed_at])
    last_contributed_at.present? && last_contributed_at >= CONTRIBUTION_DEDUPE_TTL.ago
  end

  def update_contributors(profile)
    contributors = stringify_contributors(state.fetch(:contributors, {}))
    username = profile.fetch(:username)

    contributors[contributor_key(username)] = {
      username: username,
      pet_score: profile.fetch(:pet_score, 0).to_i,
      recent_pushes_30d: profile.fetch(:recent_pushes_30d, 0).to_i,
      recent_prs_30d: profile.fetch(:recent_prs_30d, 0).to_i,
      last_active_at: profile[:last_active_at],
      top_languages: profile.fetch(:top_languages, []),
      outfit_unlocks: profile.fetch(:outfit_unlocks, []),
      last_contributed_at: Time.current.iso8601
    }

    contributors
  end

  def update_leaderboard(username, pet_score)
    existing = state.fetch(:leaderboard, []).index_by { |entry| entry.fetch(:username) }
    previous = existing[username] || { username: username, searches: 0, score: 0 }

    existing[username] = previous.merge(
      username: username,
      searches: previous.fetch(:searches, 0).to_i + 1,
      score: [previous.fetch(:score, 0).to_i, pet_score.to_i].max,
      last_seen_at: Time.current.iso8601
    )

    existing.values.sort_by { |entry| [-entry.fetch(:score, 0).to_i, entry.fetch(:username).downcase] }.first(10)
  end

  def aggregate(contributors)
    language_bytes = Hash.new(0)
    total_pushes = 0
    total_prs = 0
    active_users = 0
    shipped_recently = false

    contributors.each_value do |contributor|
      total_pushes += contributor.fetch(:recent_pushes_30d, 0).to_i
      total_prs += contributor.fetch(:recent_prs_30d, 0).to_i
      active_users += 1 if contributor.fetch(:recent_pushes_30d, 0).to_i.positive? || contributor.fetch(:recent_prs_30d, 0).to_i.positive?
      last_active_at = parse_time(contributor[:last_active_at])
      shipped_recently ||= last_active_at.present? && last_active_at >= 24.hours.ago

      contributor.fetch(:top_languages, []).each do |language|
        language_bytes[language.fetch(:name)] += language.fetch(:bytes, 0).to_i
      end
    end

    {
      total_recent_pushes: total_pushes,
      total_recent_prs: total_prs,
      active_users_count: active_users,
      unique_language_count: language_bytes.keys.length,
      dominant_language: language_bytes.max_by { |_language, bytes| bytes }&.first,
      shipped_recently: shipped_recently
    }
  end

  def community_score_for(aggregates)
    combined_push_score = [aggregates[:total_recent_pushes] * 3, 45].min
    active_user_score = [aggregates[:active_users_count] * 8, 30].min
    language_diversity_score = [aggregates[:unique_language_count] * 4, 20].min
    freshness_score = aggregates[:shipped_recently] ? 5 : 0

    [100, combined_push_score + active_user_score + language_diversity_score + freshness_score].min
  end

  def merge_outfits(profile_outfits)
    existing = state.fetch(:unlocked_outfits, []).index_by { |outfit| outfit.fetch(:id) }

    profile_outfits.each do |outfit|
      existing[outfit.fetch(:id)] ||= outfit
    end

    existing.values
  end

  def update_feed(next_state, profile, skipped_duplicate)
    label = if skipped_duplicate
      "#{profile.fetch(:username)} checked in again; no duplicate boost applied"
    else
      "#{profile.fetch(:username)} boosted the Community Pushpet"
    end

    [
      {
        type: "community_care",
        label: label,
        timestamp: Time.current.iso8601,
        metadata: {
          community_score: next_state[:community_score],
          top_caretaker: next_state.dig(:top_caretaker, :username)
        }
      },
      *state.fetch(:history, state.fetch(:feed, []))
    ].first(20)
  end

  def community_hunger(community_score)
    [[68 - (community_score / 2), 5].max, 100].min
  end

  def community_happiness(community_score, active_users_count)
    [[40 + community_score + (active_users_count * 3), 0].max, 100].min
  end

  def community_mood(community_score, skipped_duplicate)
    return "patient" if skipped_duplicate
    return "legendary" if community_score >= 90
    return "sparkly" if community_score >= 65
    return "social" if community_score >= 35

    "cozy"
  end

  def evolution_stage_for(community_score)
    return "guardian" if community_score >= 90
    return "ranger" if community_score >= 70
    return "scout" if community_score >= 45
    return "sprout" if community_score >= 20

    "hatchling"
  end

  def outfit_for(dominant_language, outfits)
    matching = outfits.find { |outfit| outfit[:source_language] == dominant_language }
    matching&.fetch(:id, nil) || state[:outfit] || DEFAULT_OUTFIT
  end

  def parse_time(timestamp)
    Time.zone.parse(timestamp.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def deep_symbolize(value)
    case value
    when Array
      value.map { |item| deep_symbolize(item) }
    when Hash
      value.to_h do |key, item|
        next [key, stringify_contributors(item)] if key.to_sym == :contributors

        [key.to_sym, deep_symbolize(item)]
      end
    else
      value
    end
  end

  def stringify_contributors(contributors)
    contributors.to_h do |key, value|
      [key.to_s, deep_symbolize(value)]
    end
  end

  def contributor_key(username)
    username.to_s.downcase
  end
end
