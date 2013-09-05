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

enable :logging

before '/' do
  @checkpoints = [Time.now]
  content_type :json
end

helpers do
  def check(stack)
    stack.push(Time.now)
    stack.reverse.take(2).reduce(:-)
  end
end

get '/' do
  app_id = params[:app_id]
  halt 400, { message: 'Invalid app_id' }.to_json unless app_id && %r{^[^/]+$} === app_id
  if value = REDIS.get(app_id)
    logger.info "Cache Hit: #{app_id} (#{ check(@checkpoints) })"
    value
  else
    logger.info "Cache Miss: #{app_id}"
    url = URI.parse("https://chrome.google.com/webstore/detail/#{ Rack::Utils.escape(app_id) }/details")
    begin
      content = url.read
      logger.info "Get #{url} (#{check(@checkpoints)})"
      doc = Mida::Document.new(content, url)
      logger.info "Parse #{url} (#{check(@checkpoints)})"
      doc.items.map(&:to_h).to_json.tap do |structure|
        REDIS.set(app_id, structure)
        logger.info "Store #{app_id} (#{ check(@checkpoints) })"
      end
    rescue OpenURI::HTTPError => e
      halt 400, { message: "Fail to access to Chrom Web Store" }.to_json
    end
  end
end
