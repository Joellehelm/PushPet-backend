ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "minitest/autorun"
require "rack/test"
require "fileutils"

class ApiTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def setup
    Rails.cache.clear
    CommunityPetState.delete_all
    LeaderboardEntry.delete_all
    IndividualPushpet.delete_all
  end

  def json
    JSON.parse(last_response.body)
  end

  def get_json(path)
    get path, {}, { "HTTP_ACCEPT" => "application/json" }
  end

  def post_json(path, payload)
    post path, payload.to_json, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json"
    }
  end

  def patch_json(path, payload)
    patch path, payload.to_json, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json"
    }
  end

  def with_github_client(client)
    original_new = GithubClient.method(:new)
    GithubClient.define_singleton_method(:new) { client }
    yield
  ensure
    GithubClient.define_singleton_method(:new) { |*args, **kwargs, &block| original_new.call(*args, **kwargs, &block) }
  end

  def active_client(username: "activecat")
    now = Time.current
    FakeGithubClient.new(
      username: username,
      events: [
        push_event(username, now - 2.hours, repo: "#{username}/shipyard", messages: ["feat: launch treat launcher", "fix: patch snack timer"]),
        push_event(username, now - 1.day, repo: "#{username}/shipyard", messages: ["docs: update readme"]),
        pull_request_event(username, now - 2.days, repo: "#{username}/shipyard", action: "closed", merged: true)
      ],
      repos: [
        repo("shipyard", username, now - 2.hours),
        repo("docs", username, now - 10.days)
      ],
      languages: {
        "shipyard" => { "TypeScript" => 12_000, "Ruby" => 3_000 },
        "docs" => { "HTML" => 2_500 }
      },
      commits: {
        "shipyard" => ["feat: launch treat launcher", "fix: patch snack timer"],
        "docs" => ["docs: write care guide"]
      }
    )
  end

  def dormant_client(username: "sleepycat")
    old_time = Time.current - 40.days
    FakeGithubClient.new(
      username: username,
      events: [
        push_event(username, old_time, repo: "#{username}/archive", messages: ["chore: tuck away toys"])
      ],
      repos: [repo("archive", username, old_time)],
      languages: { "archive" => { "Ruby" => 1_000 } },
      commits: {}
    )
  end

  def degraded_client
    client = active_client(username: "cachecat")
    client.degraded_messages << "Using cached GitHub data for /users/cachecat because GitHub is rate limiting requests."
    client
  end

  def no_push_client
    now = Time.current
    FakeGithubClient.new(
      username: "issuecat",
      events: [
        pull_request_event("issuecat", now - 3.hours, repo: "issuecat/notes", action: "opened", merged: false)
      ],
      repos: [
        repo("notes", "issuecat", now - 3.hours)
      ],
      languages: {
        "notes" => { "Python" => 2_000, "CSS" => 1_400 }
      },
      commits: {}
    )
  end

  def elided_push_payload_client
    now = Time.current
    FakeGithubClient.new(
      username: "quietpushcat",
      events: [
        {
          "type" => "PushEvent",
          "created_at" => now.iso8601,
          "repo" => { "name" => "quietpushcat/app" },
          "payload" => {
            "ref" => "refs/heads/main",
            "head" => "abc123",
            "before" => "def456"
          },
          "actor" => { "login" => "quietpushcat" }
        }
      ],
      repos: [
        repo("app", "quietpushcat", now)
      ],
      languages: {
        "app" => { "Ruby" => 1_000 }
      },
      commits: {}
    )
  end

  def not_found_client
    NotFoundGithubClient.new
  end

  def push_event(username, created_at, repo:, messages:)
    {
      "type" => "PushEvent",
      "created_at" => created_at.iso8601,
      "repo" => { "name" => repo },
      "payload" => {
        "size" => messages.length,
        "commits" => messages.map { |message| { "message" => message } }
      },
      "actor" => { "login" => username }
    }
  end

  def pull_request_event(username, created_at, repo:, action:, merged:)
    {
      "type" => "PullRequestEvent",
      "created_at" => created_at.iso8601,
      "repo" => { "name" => repo },
      "payload" => {
        "action" => action,
        "pull_request" => { "merged" => merged }
      },
      "actor" => { "login" => username }
    }
  end

  def repo(name, owner, pushed_at)
    {
      "name" => name,
      "full_name" => "#{owner}/#{name}",
      "pushed_at" => pushed_at.iso8601
    }
  end
end

class FakeGithubClient
  attr_reader :degraded_messages

  def initialize(username:, events:, repos:, languages:, commits:, degraded_messages: [])
    @username = username
    @events = events
    @repos = repos
    @languages = languages
    @commits = commits
    @degraded_messages = degraded_messages
  end

  def user(_username)
    {
      "login" => @username,
      "avatar_url" => "https://avatars.example/#{@username}.png",
      "html_url" => "https://github.com/#{@username}",
      "public_repos" => @repos.length,
      "followers" => 3
    }
  end

  def public_events(_username)
    @events
  end

  def owner_repos(_username)
    @repos
  end

  def repo_languages(_owner, repo)
    @languages.fetch(repo, {})
  end

  def commits(_owner, repo, author:, since:)
    @commits.fetch(repo, []).map do |message|
      {
        "commit" => {
          "message" => message,
          "author" => { "date" => Time.current.iso8601 }
        }
      }
    end
  end
end

class NotFoundGithubClient
  attr_reader :degraded_messages

  def initialize
    @degraded_messages = []
  end

  def user(_username)
    raise GithubClient::NotFoundError, "GitHub user not found"
  end
end
