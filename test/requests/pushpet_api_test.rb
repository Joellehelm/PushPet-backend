require_relative "../test_helper"

class PushpetApiTest < ApiTest
  def test_active_user_success
    with_github_client(active_client) do
      get_json "/api/v1/pets/activecat"
    end

    assert last_response.ok?
    pet = json.fetch("pet")

    assert_equal "activecat", pet.fetch("username")
    assert_equal "https://github.com/activecat", pet.fetch("profile_url")
    assert pet.fetch("pet_score").positive?
    assert_operator pet.fetch("level"), :>=, 1
    assert_equal "determined", pet.fetch("mood")
    assert_equal "thriving", pet.fetch("dormancy_state")
    assert_equal 3, pet.fetch("recent_pushes_7d")
    assert pet.fetch("feed_log").any? { |item| item.fetch("label").include?("Fed by") }
  end

  def test_dormant_user_success
    with_github_client(dormant_client) do
      get_json "/api/v1/pets/sleepycat"
    end

    assert last_response.ok?
    pet = json.fetch("pet")

    assert_equal "sleepycat", pet.fetch("username")
    assert_equal "ghost", pet.fetch("dormancy_state")
    assert_equal 0, pet.fetch("recent_pushes_30d")
    assert pet.fetch("feed_log").any? { |item| item.fetch("type") == "dormancy" }
  end

  def test_nonexistent_user
    with_github_client(not_found_client) do
      get_json "/api/v1/pets/not-real"
    end

    assert_equal 404, last_response.status
    assert_equal "GitHub user not found", json.fetch("error")
  end

  def test_valid_user_with_no_push_events_still_hatches
    with_github_client(no_push_client) do
      get_json "/api/v1/pets/issuecat"
    end

    assert last_response.ok?
    pet = json.fetch("pet")

    assert_equal "issuecat", pet.fetch("username")
    assert_equal 0, pet.fetch("recent_pushes_30d")
    assert_equal 1, pet.fetch("recent_prs_30d")
    assert pet.fetch("feed_log").any? { |item| item.fetch("type") == "level" }
  end

  def test_push_event_without_size_or_commits_counts_as_one_push
    with_github_client(elided_push_payload_client) do
      get_json "/api/v1/pets/quietpushcat"
    end

    assert last_response.ok?
    pet = json.fetch("pet")

    assert_equal 1, pet.fetch("recent_pushes_7d")
    assert_equal 1, pet.fetch("recent_pushes_30d")
    assert pet.fetch("pet_score").positive?
  end

  def test_degraded_rate_limited_response_path
    with_github_client(degraded_client) do
      get_json "/api/v1/pets/cachecat"
    end

    assert last_response.ok?
    pet = json.fetch("pet")

    assert_equal true, pet.fetch("degraded")
    assert_includes pet.fetch("degraded_messages").first, "rate limiting"
  end

  def test_community_pet_default_state
    get_json "/api/v1/community_pet"

    assert last_response.ok?
    community_pet = json.fetch("community_pet")

    assert_equal 0, community_pet.fetch("community_score")
    assert_equal "Pushpet Prime", community_pet.fetch("featured_name")
    assert_equal "Community Pushpet", community_pet.fetch("display_title")
    assert_equal "goat_dragon", community_pet.fetch("species")
    assert_equal "purple", community_pet.fetch("color")
    assert_equal "petplace1", community_pet.fetch("environment")
    assert_nil community_pet.fetch("top_caretaker")
  end

  def test_community_pet_updates_after_successful_username_lookup
    with_github_client(active_client) do
      get_json "/api/v1/pets/activecat"
    end

    assert last_response.ok?
    community_pet = json.fetch("community_pet")

    assert community_pet.fetch("community_score").positive?
    assert_equal 1, community_pet.fetch("contributors_count")
    assert_equal "activecat", community_pet.fetch("top_caretaker").fetch("username")
    assert_equal 3, community_pet.fetch("total_recent_pushes")
    assert_equal 2, community_pet.fetch("total_recent_prs")
  end

  def test_lookup_persists_user_in_leaderboard_without_relookup
    with_github_client(active_client) do
      get_json "/api/v1/pets/activecat"
    end

    assert last_response.ok?

    get_json "/api/v1/leaderboard"
    assert last_response.ok?
    persisted_entry = json.fetch("leaderboard").find { |entry| entry.fetch("username") == "activecat" }

    assert persisted_entry
    assert persisted_entry.fetch("score").positive?

    get_json "/api/v1/community_pet"
    assert last_response.ok?
    community_entry = json.fetch("community_pet").fetch("leaderboard").find { |entry| entry.fetch("username") == "activecat" }

    assert community_entry
  end

  def test_duplicate_username_lookup_does_not_unfairly_inflate_community_stats
    client = active_client

    with_github_client(client) { get_json "/api/v1/pets/activecat" }
    first_community_pet = json.fetch("community_pet")

    with_github_client(client) { get_json "/api/v1/pets/activecat" }
    second_community_pet = json.fetch("community_pet")

    assert_equal first_community_pet.fetch("community_score"), second_community_pet.fetch("community_score")
    assert_equal first_community_pet.fetch("total_recent_pushes"), second_community_pet.fetch("total_recent_pushes")
    assert_equal 1, second_community_pet.fetch("contributors_count")
    assert_includes second_community_pet.fetch("feed_log").first.fetch("label"), "no duplicate boost"
  end

  def test_caretaker_customization_update
    with_github_client(active_client) { get_json "/api/v1/pets/activecat" }

    patch_json "/api/v1/community_pet/customization", {
      caretaker_username: "activecat",
      title: "Snack Captain",
      name: "Treat Beacon",
      species: "star_axolotl",
      color: "blue",
      outfit: "typescript_visor",
      environment: "petplace3"
    }

    assert last_response.ok?
    community_pet = json.fetch("community_pet")

    assert_equal "Snack Captain", community_pet.fetch("display_title")
    assert_equal "Treat Beacon", community_pet.fetch("featured_name")
    assert_equal "star_axolotl", community_pet.fetch("species")
    assert_equal "blue", community_pet.fetch("color")
    assert_equal "typescript_visor", community_pet.fetch("outfit")
    assert_equal "petplace3", community_pet.fetch("environment")
    assert_equal "customization", community_pet.fetch("feed_log").first.fetch("type")

    with_github_client(dormant_client) { get_json "/api/v1/pets/sleepycat" }
    refreshed_pet = json.fetch("community_pet")

    assert_equal "Snack Captain", refreshed_pet.fetch("display_title")
    assert_equal "Treat Beacon", refreshed_pet.fetch("featured_name")
    assert_equal "star_axolotl", refreshed_pet.fetch("species")
    assert_equal "blue", refreshed_pet.fetch("color")
    assert_equal "typescript_visor", refreshed_pet.fetch("outfit")
    assert_equal "petplace3", refreshed_pet.fetch("environment")
  end

  def test_individual_pushpet_background_can_be_changed
    with_github_client(active_client) do
      post_json "/api/v1/pets/activecat/hatch", {
        species: "star_axolotl",
        color: "purple",
        background: "petplace2"
      }
    end

    assert last_response.ok?
    assert_equal "petplace2", json.fetch("pushpet").fetch("background")

    patch_json "/api/v1/pets/activecat/background", {
      background: "petplace3"
    }

    assert last_response.ok?
    assert_equal "petplace3", json.fetch("pushpet").fetch("background")
  end

  def test_individual_pushpet_customization_can_change_name_style_and_place
    with_github_client(active_client) do
      post_json "/api/v1/pets/activecat/hatch", {
        species: "star_axolotl",
        color: "purple",
        background: "petplace2"
      }
    end

    assert last_response.ok?

    patch_json "/api/v1/pets/activecat/customization", {
      display_name: "Snack Sprite",
      species: "raccoon",
      color: "green",
      background: "petplace3"
    }

    assert last_response.ok?
    pushpet = json.fetch("pushpet")
    assert_equal "Snack Sprite", pushpet.fetch("display_name")
    assert_equal "raccoon", pushpet.fetch("species")
    assert_equal "green", pushpet.fetch("color")
    assert_equal "petplace3", pushpet.fetch("background")

    patch_json "/api/v1/pets/activecat/customization", {
      color: "orange"
    }

    assert last_response.ok?
    pushpet = json.fetch("pushpet")
    assert_equal "Snack Sprite", pushpet.fetch("display_name")
    assert_equal "raccoon", pushpet.fetch("species")
    assert_equal "orange", pushpet.fetch("color")
    assert_equal "petplace3", pushpet.fetch("background")
  end

  def test_invalid_users_do_not_affect_community_pet
    get_json "/api/v1/community_pet"
    before = json.fetch("community_pet")

    with_github_client(not_found_client) do
      get_json "/api/v1/pets/not-real"
    end

    assert_equal 404, last_response.status

    get_json "/api/v1/community_pet"
    after = json.fetch("community_pet")

    assert_equal before.fetch("community_score"), after.fetch("community_score")
    assert_equal before.fetch("contributors_count"), after.fetch("contributors_count")
    assert_nil after.fetch("top_caretaker")
  end
end
