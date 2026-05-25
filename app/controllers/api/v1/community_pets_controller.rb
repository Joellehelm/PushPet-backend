module Api
  module V1
    class CommunityPetsController < ApplicationController
      def show
        render json: { community_pet: CommunityPetStore.instance.current }
      end

      def update
        community_pet = CommunityPetStore.instance.update_customization(
          caretaker_username: customization_params[:caretaker_username],
          title: customization_params[:title],
          name: customization_params[:name],
          outfit: customization_params[:outfit],
          environment: customization_params[:environment]
        )

        render json: { community_pet: community_pet }
      rescue CommunityPetStore::CustomizationError => error
        render json: { error: error.message }, status: :forbidden
      end

      private

      def customization_params
        params.to_unsafe_h.slice("caretaker_username", "title", "name", "outfit", "environment").symbolize_keys
      end
    end
  end
end
