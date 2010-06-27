require 'setup'

require 'sinatra/base'
require 'haml'
require 'sass'
require 'yajl'
require 'bcrypt'
require 'securerandom'

require 'mongo'
CONN = Mongo::Connection.new
DB = CONN.db('hotspots')

def ObjectID(str)
  Mongo::ObjectID.from_string(str)
end

class Hotspots < Sinatra::Base
  before do
    @db = DB.collection('github')
  end

  get '/' do
    haml :foobar
  end

  get '/stats' do
    # result = @db.map_reduce(
    #   "function(){
    #     var t = this.tracers,
    #         result = {
    #           time: [this.time],
    #           objects_created: [],
    #           gc_time: [],
    #           mysql_time: [],
    #           memcache_get_responses_notfound: []
    #         };
    #     
    #   }",
    #   "function(){
    #     
    #   }"
    # )

    result = @db.map_reduce(
      "function(){
        var t = this.tracers;
        var result = {
          time: [this.time],
          objects_created: [t.objects.created],
          gc_time: [t.gc.time],
          mysql_time: [],
          memcache_get_responses_notfound: []
        };

        if (t.memcache && t.memcache.get && t.memcache.get.responses && t.memcache.get.responses.notfound)
          result.memcache_get_responses_notfound.push(t.memcache.get.responses.notfound);

        if (t.mysql && t.mysql.time)
          result.mysql_time.push(t.mysql.time);

        emit(
          this.rails.controller + '#' + this.rails.action,
          result
        );
      }",
      "function(key,vals){
        var result = {
          time: [],
          objects_created: [],
          gc_time: [],
          mysql_time: [],
          memcache_get_responses_notfound: []
        };

        for (var i in vals) {
          var val = vals[i];
          for (var f in val) {
            result[f].push.apply(result[f], val[f]);
          }
        }

        return result;
      }",
      :sort => ['value.time.count', :desc],
      :finalize => 'function(key, val){
        var result = {};

        for (var f in val) {
          var list = val[f];
          list.sort(function(a,b){ return a-b; });

          for(var i=0,sum=0; i<list.length; sum+=list[i++]);

          result[f] = {
            count: list.length,
            min: list[0],
            max: list[list.length-1]
          };

          if (result[f].count)
            result[f].avg = sum/result[f].count;
        }

        return result;
      }'
    )

    p result
    p result.count
    @result = result

    haml :stats
  end

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static, :logging, :inline_templates
  use Rack::Session::Cookie, :key => 'memprof_hotspots', :secret => 'noisses_forpmem', :expire_after => 2592000
end

if __FILE__ == $0
  Hotspots.run!
end

__END__

@@ foobar
hello world!

@@ stats
%table
  %thead
    %tr
      %th action
      %th 
  %tbody
    - @result.find.limit(10).each do |row|
      %tr
        %td
          %p
            %pre= row.inspect
