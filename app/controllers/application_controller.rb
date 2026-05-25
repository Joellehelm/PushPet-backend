class ApplicationController < ActionController::API
  before_action :force_json_format

  private

  def force_json_format
    request.format = :json
  end
end
