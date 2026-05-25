module Api
  module V1
    class PetsController < ApplicationController
      def show
        username = params[:username].to_s.strip
        return render json: { error: "Username is required" }, status: :bad_request if username.blank?

        profile = GithubPetProfileBuilder.new(username: username).call
        pushpet = IndividualPushpet.find_by_username(profile.fetch(:username))
        LeaderboardEntry.record!(profile: profile, pushpet: pushpet)
        community_pet = CommunityPetStore.instance.apply_profile(profile)

        render json: {
          pet: profile,
          pushpet: pushpet&.as_api,
          leaderboard: LeaderboardEntry.top.map(&:as_api),
          community_pet: community_pet
        }
      rescue GithubClient::NotFoundError
        render json: { error: "GitHub user not found" }, status: :not_found
      rescue GithubClient::RateLimitError => error
        render json: { error: error.message }, status: :too_many_requests
      rescue GithubClient::RequestError => error
        render json: { error: error.message }, status: :bad_gateway
      end

      def hatch
        username = params[:username].to_s.strip
        return render json: { error: "Username is required" }, status: :bad_request if username.blank?

        profile = GithubPetProfileBuilder.new(username: username).call
        pushpet = IndividualPushpet.find_by_username(profile.fetch(:username))

        if pushpet.nil?
          pushpet = IndividualPushpet.create!(
            username: profile.fetch(:username),
            species: hatch_params[:species],
            color: hatch_params[:color],
            background: hatch_params[:background],
            hatched_at: Time.current
          )
        end

        LeaderboardEntry.record!(profile: profile, pushpet: pushpet)
        community_pet = CommunityPetStore.instance.apply_profile(profile)

        render json: {
          pet: profile,
          pushpet: pushpet.as_api,
          leaderboard: LeaderboardEntry.top.map(&:as_api),
          community_pet: community_pet
        }
      rescue GithubClient::NotFoundError
        render json: { error: "GitHub user not found" }, status: :not_found
      rescue GithubClient::RateLimitError => error
        render json: { error: error.message }, status: :too_many_requests
      rescue GithubClient::RequestError => error
        render json: { error: error.message }, status: :bad_gateway
      rescue ActiveRecord::RecordInvalid => error
        render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def equipment
        pushpet = IndividualPushpet.find_by_username(params[:username])
        return render json: { error: "Pushpet has not been hatched yet" }, status: :not_found unless pushpet

        pushpet.equip!(slot: equipment_params[:slot], accessory: equipment_params[:accessory])
        render json: {
          pushpet: pushpet.as_api,
          leaderboard: LeaderboardEntry.top.map(&:as_api)
        }
      end

      def background
        pushpet = IndividualPushpet.find_by_username(params[:username])
        return render json: { error: "Pushpet has not been hatched yet" }, status: :not_found unless pushpet

        pushpet.update_background!(background: background_params[:background])
        LeaderboardEntry.find_or_initialize_by_username(pushpet.username).update!(
          species: pushpet.species,
          color: pushpet.color,
          accessory: pushpet.accessory,
          equipped_accessories: pushpet.equipped_accessories,
          background: pushpet.background
        )

        render json: {
          pushpet: pushpet.as_api,
          leaderboard: LeaderboardEntry.top.map(&:as_api)
        }
      end

      private

      def hatch_params
        params.to_unsafe_h.slice("species", "color", "background").symbolize_keys
      end

      def equipment_params
        params.to_unsafe_h.slice("slot", "accessory").symbolize_keys
      end

      def background_params
        params.to_unsafe_h.slice("background").symbolize_keys
      end
    end
  end
end
