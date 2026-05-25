require "set"

class GithubPetProfileBuilder
  LANGUAGE_REPO_LIMIT = 10
  COMMIT_ENRICHMENT_REPO_LIMIT = 3

  OUTFITS_BY_LANGUAGE = {
    "Ruby" => { id: "ruby_crown", label: "Ruby crown" },
    "JavaScript" => { id: "javascript_shades", label: "JavaScript shades" },
    "TypeScript" => { id: "typescript_visor", label: "TypeScript visor" },
    "Python" => { id: "python_wizard_hat", label: "Python wizard hat" },
    "Go" => { id: "go_jetpack", label: "Go jetpack" },
    "Rust" => { id: "rust_armor_accent", label: "Rust armor accent" }
  }.freeze

  STAGE_NAMES = [
    [90, "guardian"],
    [70, "ranger"],
    [45, "scout"],
    [20, "sprout"],
    [0, "hatchling"]
  ].freeze

  LEVEL_NAMES = {
    1 => "Hatchling",
    2 => "Sprout",
    3 => "Scout",
    4 => "Ranger",
    5 => "Guardian",
    6 => "Legend"
  }.freeze

  def initialize(username:, client: GithubClient.new)
    @username = username
    @client = client
  end

  def call
    Rails.cache.fetch("pushpet:profile:v3:#{normalized_username}", expires_in: 3.minutes) { build_profile }
  end

  private

  attr_reader :username, :client

  def build_profile
    user = client.user(username)
    events = client.public_events(username)
    repos = client.owner_repos(username)
    top_languages = fetch_languages(user.fetch("login"), repos)
    commit_messages = recent_commit_messages(user.fetch("login"), events, repos)
    metrics = activity_metrics(events, repos)
    pet_score = score_for(metrics)
    level = 1 + (pet_score / 15).floor
    dormancy_state = dormancy_state_for(metrics[:last_active_at])
    mood = mood_for(commit_messages, events)
    outfit_unlocks = unlocked_outfits(top_languages)
    feed_log = feed_for(metrics, pet_score, level, mood, dormancy_state, outfit_unlocks)

    {
      username: user.fetch("login"),
      avatar_url: user["avatar_url"],
      profile_url: user["html_url"],
      pet_score: pet_score,
      level: level,
      evolution_stage: evolution_stage_for(pet_score),
      mood: mood,
      hunger: hunger_for(pet_score, dormancy_state),
      happiness: happiness_for(pet_score, metrics[:streak_days], dormancy_state),
      streak_days: metrics[:streak_days],
      recent_pushes_7d: metrics[:recent_pushes_7d],
      recent_pushes_30d: metrics[:recent_pushes_30d],
      recent_prs_30d: metrics[:recent_prs_30d],
      active_repo_count_30d: metrics[:active_repo_count_30d],
      last_active_at: metrics[:last_active_at]&.iso8601,
      dormancy_state: dormancy_state,
      top_languages: top_languages,
      outfit_unlocks: outfit_unlocks,
      recent_commit_messages: commit_messages.first(8),
      history: feed_log,
      feed_log: feed_log,
      summary_text: summary_text(user.fetch("login"), pet_score, level, mood, dormancy_state),
      degraded: client.degraded_messages.any?,
      degraded_messages: client.degraded_messages
    }
  end

  def activity_metrics(events, repos)
    pushes_7d = 0
    pushes_30d = 0
    opened_or_closed_prs_30d = 0
    merged_prs_30d = 0
    active_days_14d = Set.new
    active_repos_30d = Set.new
    timestamps = []

    events.each do |event|
      created_at = parse_time(event["created_at"])
      next unless created_at

      timestamps << created_at
      active_days_14d << created_at.to_date if created_at >= 14.days.ago
      repo_name = event.dig("repo", "name")
      active_repos_30d << repo_name if repo_name.present? && created_at >= 30.days.ago

      if event["type"] == "PushEvent"
        push_count = event.dig("payload", "size").to_i
        push_count = event.dig("payload", "commits").to_a.length if push_count.zero?
        pushes_30d += push_count if created_at >= 30.days.ago
        pushes_7d += push_count if created_at >= 7.days.ago
      elsif event["type"] == "PullRequestEvent" && created_at >= 30.days.ago
        action = event.dig("payload", "action").to_s
        pull_request = event.dig("payload", "pull_request") || {}
        merged = pull_request["merged"] == true
        merged_prs_30d += 1 if merged
        opened_or_closed_prs_30d += 1 if %w[opened closed reopened].include?(action)
      end
    end

    repos.each do |repo|
      pushed_at = parse_time(repo["pushed_at"])
      next unless pushed_at

      timestamps << pushed_at
      active_repos_30d << repo["full_name"] if pushed_at >= 30.days.ago
    end

    {
      recent_pushes_7d: pushes_7d,
      recent_pushes_30d: pushes_30d,
      merged_prs_30d: merged_prs_30d,
      opened_or_closed_prs_30d: opened_or_closed_prs_30d,
      recent_prs_30d: merged_prs_30d + opened_or_closed_prs_30d,
      active_days_14d: active_days_14d.length,
      streak_days: streak_from_events(events),
      active_repo_count_30d: active_repos_30d.compact.length,
      last_active_at: timestamps.compact.max
    }
  end

  def score_for(metrics)
    pushes_7d = metrics[:recent_pushes_7d]
    pushes_30d = metrics[:recent_pushes_30d]
    push_score = (pushes_7d * 8) + ([pushes_30d - pushes_7d, 0].max * 3)
    pr_score = (metrics[:merged_prs_30d] * 4) + (metrics[:opened_or_closed_prs_30d] * 1)
    consistency_score = (metrics[:active_days_14d] * 2) + ([metrics[:streak_days], 14].min * 2)
    repo_score = metrics[:active_repo_count_30d] * 2

    [100, push_score + pr_score + consistency_score + repo_score].min
  end

  def fetch_languages(owner, repos)
    totals = Hash.new(0)

    repos.first(LANGUAGE_REPO_LIMIT).each do |repo|
      client.repo_languages(owner, repo.fetch("name")).each do |language, bytes|
        totals[language] += bytes.to_i
      end
    rescue GithubClient::RequestError
      next
    end

    totals.sort_by { |_language, bytes| -bytes }.map do |language, bytes|
      {
        name: language,
        bytes: bytes,
        outfit: OUTFITS_BY_LANGUAGE[language]&.fetch(:id, nil)
      }
    end
  end

  def recent_commit_messages(owner, events, repos)
    messages = events.flat_map do |event|
      next [] unless event["type"] == "PushEvent"

      event.dig("payload", "commits").to_a.filter_map { |commit| commit["message"].to_s.lines.first&.strip.presence }
    end

    repos.first(COMMIT_ENRICHMENT_REPO_LIMIT).each do |repo|
      break if messages.length >= 8

      client.commits(owner, repo.fetch("name"), author: username, since: 30.days.ago.iso8601).each do |commit|
        message = commit.dig("commit", "message").to_s.lines.first&.strip
        messages << message if message.present?
      end
    rescue GithubClient::RequestError
      next
    end

    messages.uniq.first(12)
  end

  def feed_for(metrics, pet_score, level, mood, dormancy_state, outfit_unlocks)
    feed = [
      {
        type: "hatch",
        label: "Pushpet hatched with #{pet_score} care points",
        timestamp: Time.current.iso8601,
        metadata: { score: pet_score }
      }
    ]

    if metrics[:recent_pushes_7d].positive?
      feed << {
        type: "pushes",
        label: "Fed by #{metrics[:recent_pushes_7d]} pushes",
        timestamp: metrics[:last_active_at]&.iso8601,
        metadata: { pushes_7d: metrics[:recent_pushes_7d] }
      }
    end

    feed << {
      type: "level",
      label: "Leveled up to #{level_name(level)}",
      timestamp: Time.current.iso8601,
      metadata: { level: level }
    }

    outfit_unlocks.first(3).each do |outfit|
      feed << {
        type: "outfit",
        label: "Unlocked #{outfit[:label]}",
        timestamp: Time.current.iso8601,
        metadata: { outfit: outfit[:id], language: outfit[:source_language] }
      }
    end

    feed << {
      type: "mood",
      label: "Mood changed to #{mood}",
      timestamp: Time.current.iso8601,
      metadata: { mood: mood }
    }

    if dormancy_state != "thriving"
      quiet_days = quiet_days_from(metrics[:last_active_at])
      feed << {
        type: "dormancy",
        label: "Went #{dormancy_state} after #{quiet_days} quiet days",
        timestamp: metrics[:last_active_at]&.iso8601,
        metadata: { dormancy_state: dormancy_state, quiet_days: quiet_days }
      }
    end

    if metrics[:recent_pushes_30d].zero? && metrics[:recent_prs_30d].zero?
      feed << {
        type: "quiet",
        label: "No recent pushes yet, still hatchable",
        timestamp: Time.current.iso8601
      }
    end

    feed.first(12)
  end

  def unlocked_outfits(languages)
    languages.filter_map do |language|
      outfit = OUTFITS_BY_LANGUAGE[language[:name]]
      next unless outfit

      {
        id: outfit[:id],
        label: outfit[:label],
        source_language: language[:name]
      }
    end
  end

  def mood_for(commit_messages, events)
    text = commit_messages.join(" ").downcase
    return "determined" if text.match?(/\b(fix|bug|patch)\b/)
    return "hyped" if text.match?(/\b(feat|release|ship|launch)\b/)
    return "thoughtful" if text.match?(/\b(docs|readme|guide)\b/)
    return "tidy" if text.match?(/\b(refactor|cleanup|chore)\b/)

    event_mix_mood(events)
  end

  def event_mix_mood(events)
    recent_types = events.select { |event| parse_time(event["created_at"])&.>= 14.days.ago }.map { |event| event["type"] }
    return "hyped" if recent_types.count("ReleaseEvent").positive?
    return "social" if recent_types.count("PullRequestEvent") >= 2
    return "focused" if recent_types.count("PushEvent") >= 3
    return "curious" if recent_types.any?

    "cozy"
  end

  def streak_from_events(events)
    event_days = events.filter_map { |event| parse_time(event["created_at"])&.to_date }.uniq
    today = Time.zone.today
    streak = 0

    while event_days.include?(today - streak.days)
      streak += 1
    end

    streak
  end

  def dormancy_state_for(last_active_at)
    return "ghost" unless last_active_at

    quiet_hours = ((Time.current - last_active_at) / 1.hour).floor
    return "thriving" if quiet_hours <= 24
    return "okay" if quiet_hours <= 72
    return "peckish" if quiet_hours <= 168
    return "sad" if quiet_hours <= 336

    "ghost"
  end

  def quiet_days_from(last_active_at)
    return 30 unless last_active_at

    [(Time.current.to_date - last_active_at.to_date).to_i, 0].max
  end

  def hunger_for(pet_score, dormancy_state)
    penalty = { "thriving" => 0, "okay" => 10, "peckish" => 24, "sad" => 40, "ghost" => 55 }.fetch(dormancy_state)
    [[70 - (pet_score / 2) + penalty, 0].max, 100].min
  end

  def happiness_for(pet_score, streak_days, dormancy_state)
    penalty = { "thriving" => 0, "okay" => 8, "peckish" => 22, "sad" => 38, "ghost" => 55 }.fetch(dormancy_state)
    [[35 + pet_score + ([streak_days, 14].min * 2) - penalty, 0].max, 100].min
  end

  def evolution_stage_for(pet_score)
    STAGE_NAMES.find { |score, _stage| pet_score >= score }.last
  end

  def level_name(level)
    LEVEL_NAMES.fetch(level, "Legend")
  end

  def summary_text(username, pet_score, level, mood, dormancy_state)
    "#{username}'s Pushpet is a level #{level} #{mood} #{evolution_stage_for(pet_score)} with #{pet_score} care points and #{dormancy_state} energy."
  end

  def parse_time(timestamp)
    Time.zone.parse(timestamp.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalized_username
    username.to_s.strip.downcase
  end
end
