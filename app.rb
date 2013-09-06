require 'json'
require 'mida'
require 'open-uri'
require 'sinatra'
require 'dalli'

configure :production do
  CACHE = Dalli::Client.new(ENV['MEMCACHED_SERVERS'], username: ENV['MEMCACHED_USERNAME'], password: ENV['MEMCACHED_PASSWORD'])
end

configure :development, :test do
  CACHE = Dalli::Client.new
end

set :public_folder do
  File.join(settings.root, 'public')
end
set :cache_expire, 60 * 5 # 5 minutes

set :td_database do
  "microjson_#{settings.environment}"
end
set :td_table, "events"

helpers do
  def td(object = {})
    $stdout.puts("@[%s.%s] %s" % [settings.td_database, settings.td_table, object.merge(time: Time.now.to_i).to_json])
  end
end

get '/' do
  erb :index
end

get '/microdata' do
  redirect '/'
end

get '/microdata/chrome_store' do
  redirect '/'
end

get '/microdata/chrome_store/:app_id.json' do
  content_type :json
  app_id = params[:app_id]
  halt 400, { message: 'Invalid app_id' }.to_json unless app_id && %r{^[^/]+$} === app_id
  if value = CACHE.get(app_id)
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
        CACHE.set(app_id, structure, settings.cache_expire)
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

__END__
@@ layout
<!DOCTYPE html>
<html
  itemtype="http://schema.org/WebPage"
  itemscope>
  <head>
    <meta charset="utf-8">
    <meta itemprop="url" content="<%= url('/') %>">
    <meta name="description" content="Convert Microdata included markup into JSON">
    <meta itemprop="name" content="Microjson">
    <meta itemprop="image" content="<%= url("/images/logo.png") %>">
    <title>Microjson :: Microdata -&gt; JSON</title>
  </head>
  <body>
    <%= yield %>
    <address itemprop="author" itemtype="http://schema.org/Person" itemscope>
      <p><span itemprop="name">aereal</span>, <a rel="author" href="http://aereal.org/" itemprop="url">aereal.org</a>, <span itemprop="email">aereal@aereal.org</span></p>
    </address>
    <script>
      (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
      (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
      m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
      })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

      ga('create', 'UA-43801314-1', 'microjson.herokuapp.com');
      ga('send', 'pageview');
    </script>
  </body>
</html>

@@ index
<section>
  <h1>Microjson</h1>
  <p itemprop="description">Convert Microdata included markup into JSON</p>
  <section>
    <h2>Chrome Web Store</h2>
    <p>
      <a href="https://chrome.google.com/webstore/detail/%E3%81%AF%E3%81%A6%E3%81%AA%E3%83%96%E3%83%83%E3%82%AF%E3%83%9E%E3%83%BC%E3%82%AF-googlechrome-%E6%8B%A1%E5%BC%B5/dnlfpnhinnjdgmjfpccajboogcjocdla">はてなブックマーク GoogleChrome 拡張</a>
      -&gt;
      <a href="/microdata/chrome_store/dnlfpnhinnjdgmjfpccajboogcjocdla.json">/microdata/chrome_store/dnlfpnhinnjdgmjfpccajboogcjocdla.json</a>
    </p>
  </section>
</section>
