module Api
  module V1
    class LeaderboardsController < ApplicationController
      def show
        render json: { leaderboard: LeaderboardEntry.top.map(&:as_api) }
      end
    end
  end
end
