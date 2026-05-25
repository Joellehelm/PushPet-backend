require "cgi"
require "json"
require "net/http"

class GithubClient
  API_ROOT = "https://api.github.com"
  CACHE_TTL = 5.minutes
  OPEN_TIMEOUT = 4
  READ_TIMEOUT = 8
  WRITE_TIMEOUT = 4

  class RequestError < StandardError; end
  class NotFoundError < RequestError; end
  class RateLimitError < RequestError; end

  attr_reader :degraded_messages

  def initialize
    @degraded_messages = []
  end

  def user(username)
    get_json("/users/#{escape(username)}")
  end

  def public_events(username)
    get_json("/users/#{escape(username)}/events/public")
  end

  def owner_repos(username)
    get_json("/users/#{escape(username)}/repos?type=owner&sort=pushed&direction=desc&per_page=100")
  end

  def repo_languages(owner, repo)
    get_json("/repos/#{escape(owner)}/#{escape(repo)}/languages")
  end

  def commits(owner, repo, author:, since:)
    get_json("/repos/#{escape(owner)}/#{escape(repo)}/commits?author=#{escape(author)}&since=#{escape(since)}&per_page=100")
  end

  private

  def get_json(path)
    cache_key = "github:v1:#{path}"
    cached = Rails.cache.read(cache_key)
    return cached[:body] if cached && cached[:fresh_until].future?

    uri = URI("#{API_ROOT}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "Pushpet"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["Authorization"] = "Bearer #{github_token}" if github_token.present?
    request["If-None-Match"] = cached[:etag] if cached&.dig(:etag).present?

    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: true,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT,
      write_timeout: WRITE_TIMEOUT
    ) do |http|
      http.request(request)
    end

    case response
    when Net::HTTPSuccess
      body = JSON.parse(response.body)
      Rails.cache.write(cache_key, cache_payload(response, body), expires_in: CACHE_TTL * 2)
      body
    when Net::HTTPNotModified
      body = cached.fetch(:body)
      Rails.cache.write(cache_key, cache_payload(response, body), expires_in: CACHE_TTL * 2)
      body
    when Net::HTTPNotFound
      raise NotFoundError, "GitHub resource not found"
    when Net::HTTPForbidden, Net::HTTPTooManyRequests
      return degraded_cached_body(path, cached) if cached&.dig(:body)

      retry_after = response["Retry-After"]
      message = "GitHub is rate limiting requests. Please retry"
      message += " in #{retry_after} seconds" if retry_after.present?
      raise RateLimitError, "#{message}."
    else
      raise RequestError, "GitHub request failed with #{response.code}"
    end
  rescue JSON::ParserError
    raise RequestError, "GitHub returned invalid JSON"
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => error
    raise RequestError, "GitHub request failed: #{error.message}"
  end

  def cache_payload(response, body)
    {
      body: body,
      etag: response["ETag"],
      fresh_until: CACHE_TTL.from_now
    }
  end

  def degraded_cached_body(path, cached)
    @degraded_messages << "Using cached GitHub data for #{path} because GitHub is rate limiting requests."
    cached.fetch(:body)
  end

  def github_token
    ENV["GITHUB_TOKEN"].presence || ENV["GITHUB_API_TOKEN"].presence
  end

  def escape(value)
    CGI.escape(value.to_s)
  end
end
