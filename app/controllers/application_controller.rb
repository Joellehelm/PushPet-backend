class ApplicationController < ActionController::API
  before_action :force_json_format
  rescue_from ActiveRecord::ActiveRecordError, with: :render_database_unavailable

  private

  def force_json_format
    request.format = :json
  end

  def render_database_unavailable(error)
    Rails.logger.error("[database] #{error.class}: #{error.message}")

    render json: {
      error: "PushPet database is unavailable. Check DATABASE_URL and run migrations.",
      detail: error.class.name
    }, status: :service_unavailable
  end
end
