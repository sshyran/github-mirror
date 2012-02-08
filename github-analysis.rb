

require 'rubygems'
require 'mongo'
require 'yaml'
require 'json'
require 'net/http'
require 'logger'
require 'set'
require 'open-uri'

# Mongo preparation

# db.createCollection("commits")
# db.owners.ensureIndex({'commits.id': 1})
# db.createCollection("owners")
# db.owners.ensureIndex({pr: 1})

class GithubAnalysis

  attr_reader :num_api_calls
  attr_reader :settings
  attr_reader :log

  def initialize
    @settings = YAML::load_file "config.yaml"
    get_mongo
    @ts = Time.now().tv_sec()
    @num_api_calls = 0
    @log = Logger.new(STDOUT)
  end

  # Mongo related functions
  def get_mongo
    @db = Mongo::Connection.new(@settings['mongo']['host'],
                                @settings['mongo']['port'])\
                           .db(@settings['mongo']['db'])
    #@db.authenticate(@settings['mongo']['username'],
    #                 @settings['mongo']['password'])
    @db
  end

  def commits_col
    @db.collection(@settings['mongo']['commits'])
  end

  def commits_col_v3
    @db.collection(@settings['mongo']['commitsv3'])
  end

  def events_col
    @db.collection(@settings['mongo']['events'])
  end

  # Specific API call functions and caches

  # Get commit information.
  # This method uses the v2 API for retrieving commits as v3 does not include
  # the commit diff.
  def get_commit_v2 user, repo, sha
    url = "http://github.com/api/v2/json/commits/show/%s/%s/%s"
    get_commit url, commits_col, 'commit.id', user, repo, sha
  end

  # Get commit information.
  # This method uses the v3 API for retrieving commits
  def get_commit_v3 user, repo, sha
    url = @settings['mirror']['urlbase'] + "repos/%s/%s/commits/%s"
    get_commit url, commits_col_v3, 'sha', user, repo, sha
  end

  def get_events
    api_request "https://api.github.com/events"
  end

  private

  def get_commit urltmpl, col, commit_id, user, repo, sha
    if not sha.match(/[a-f0-9]{40}$/) then
        @log.warn "Ignoring #{line}"
        return
    end

    if col.find({"#{commit_id}" => "#{sha}"}).has_next? then
        @log.info "Already got #{sha}"
    else
        result = api_request urltmpl%[user, repo, sha]
        col.insert(result)
        @log.info "Added #{sha}"
    end
  end


  def api_request url
    #Rate limiting to avoid error requests
    if Time.now().tv_sec() - @ts < 60 then
      if @num_api_calls >= 50 then
        @log.debug "Sleeping for #{Time.now().tv_sec() - @ts}"
        sleep (Time.now().tv_sec() - @ts)
        @num_api_calls = 0
        @ts = Time.now().tv_sec()
      end
    else
      @num_api_calls = 0
      @ts = Time.now().tv_sec()
    end

    @num_api_calls += 1
    @log.debug("Opening URL: #{url}")
    uri = open(url).read
    #resp = Net::HTTP.get_response(URI.parse(url))
    return JSON.parse(uri)
  end
end
