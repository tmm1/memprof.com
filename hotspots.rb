require 'setup'

require 'sinatra/base'
require 'haml'
require 'sass'
require 'yajl'
require 'bcrypt'
require 'securerandom'

require 'action_view/helpers/number_helper'
require 'i18n'
require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/hash/reverse_merge'
require 'active_support/core_ext/string/output_safety'

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
    @result = DB.collection('github_stats')
    haml :stats
  end

  get '/generate' do
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
      :finalize => %[function(key, val){
        var stats = function(data) {
            data.sort(function(a,b){ return a-b; });

            var s = {};
            s.count = data.length;
            if (!s.count)
              return s;

            s.min = data[0];
            s.max = data[data.length - 1];

            var calc_median = function(pos, len) {
              if ((len % 2) != 0)
                  return data[pos];
              else
                  return (data[pos - 1] + data[pos]) / 2;
            }

            var middle = Math.floor(data.length / 2);

            s.median = calc_median(middle,                          data.length);
            s.q1     = calc_median(Math.floor(middle / 2),          middle);
            s.q2     = calc_median(Math.floor(data.length * 0.75),  data.length - middle);

            var i=0, sum=0
            for(; i < list.length; sum += list[i++]);

            s.avg = sum / s.count;
            return s;
        }

        var result = {};

        for (var f in val) {
          var list = val[f];
          result[f] = stats(list);

          // list.sort(function(a,b){ return a-b; });
          // 
          // for(var i=0,sum=0; i<list.length; sum+=list[i++]);
          // 
          // result[f] = {
          //   count: list.length,
          //   min: list[0],
          //   max: list[list.length-1]
          // };
          // 
          // if (result[f].count)
          //   result[f].avg = sum/result[f].count;
        }

        return result;
      }],
      :out => 'github_stats'
    )

    "Done w/ #{result.count} entries"
  end

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html
    include ActionView::Helpers::NumberHelper
    def number_with_delimiter(num,opts={})
      super(num, opts.merge(:delimiter => ',', :separator => '.'))
    end

    def data_format(data, format)
      if format == '%d'
        number_with_delimiter(data.to_i)
      else
        format % data
      end
    end
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static, :logging
  # enable :inline_templates
  use Rack::Session::Cookie, :key => 'memprof_hotspots', :secret => 'noisses_forpmem', :expire_after => 2592000
end

if __FILE__ == $0
  Hotspots.run!
end
