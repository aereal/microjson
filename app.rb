require 'json'
require 'mida'
require 'open-uri'
require 'sinatra'
require 'redis'

REDIS =
  begin
    require 'hiredis'
    Redis.new(driver: :hiredis)
  rescue LoadError
    Redis.new
  end

set :td_table, "microjson.development"

before '/' do
  content_type :json
end

helpers do
  def td(object = {})
    $stdout.puts("@%s %s" % [settings.td_table, object.merge(time: Time.now.to_i).to_json])
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
