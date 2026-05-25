if Rails.env.production? && ENV["DATABASE_URL"].blank?
  raise KeyError, "DATABASE_URL is required in production"
end
