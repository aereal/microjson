require 'json'
require 'mida'
require 'open-uri'
require 'sinatra'
require 'redis'

configure :production do
  redis_url = URI.parse(ENV['REDIS_URL'])
  set :redis, {
    host: redis_url.host,
    port: redis_url.port,
    password: redis_url.password,
  }
end

configure :development, :test do
  set :redis, {}
end

configure do
  REDIS =
    begin
      require 'hiredis'
      Redis.new(settings.redis.merge(driver: :hiredis))
    rescue LoadError
      Redis.new(settings.redis)
    end
end

set :td_database do
  "microjson.#{settings.environment}"
end
set :td_table, "events"

before '/' do
  content_type :json
end

helpers do
  def td(object = {})
    $stdout.puts("@%s.%s %s" % [settings.td_database, settings.td_table, object.merge(time: Time.now.to_i).to_json])
  end
end

get '/' do
  app_id = params[:app_id]
  halt 400, { message: 'Invalid app_id' }.to_json unless app_id && %r{^[^/]+$} === app_id
  if value = REDIS.get(app_id)
    td app_id: app_id, event: :cache_hit
    value
  else
    td app_id: app_id, event: :cache_miss
    url = URI.parse("https://chrome.google.com/webstore/detail/#{ Rack::Utils.escape(app_id) }/details")
    begin
      content = url.read
      td app_id: app_id, event: :get_url
      doc = Mida::Document.new(content, url)
      td app_id: app_id, event: :parse_html
      doc.items.map(&:to_h).to_json.tap do |structure|
        REDIS.set(app_id, structure)
      end
    rescue OpenURI::HTTPError => e
      case e.io.status.first
      when '404'
        td app_id: app_id, event: :not_found
        halt 404, { message: "Not Found" }.to_json
      else
        td app_id: app_id, event: :fail_get_url
        halt 400, { message: "Fail to access to Chrom Web Store" }.to_json
      end
    end
  end
end
