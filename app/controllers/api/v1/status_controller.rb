module Api
  module V1
    class StatusController < ApplicationController
      def show
        ActiveRecord::Base.connection.select_value("SELECT 1")

        render json: {
          status: "ok",
          database: {
            status: "ok"
          }
        }
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.error("[database-status] #{error.class}: #{error.message}")

        render json: {
          status: "degraded",
          database: {
            status: "error",
            detail: error.class.name
          }
        }, status: :service_unavailable
      end
    end
  end
end
