require 'setup'
require 'mongo'
CONN = Mongo::Connection.new
DB = CONN.db('memprof_site')

def ObjectID(str)
  Mongo::ObjectID.from_string(str)
end

class Regexp
  def to_json()
    Yajl.dump :$regex => to_s
  end
end

require 'sequel/extensions/pretty_table'

class Mongo::Collection
  def print
    find.print
  end
end

class Mongo::Cursor
  def inspect
    str = "#{@full_collection_name}.find"
    str << "(#{@selector.inspect})" unless @selector.empty?
    str << ".limit(#{@limit})" if @limit > 0
    str
  end

  def print
    num = count
    puts "#{inspect}: #{num} results"
    if num > 0
      results = limit(10).to_a
      Sequel::PrettyTable.print(results.map!{ |r| r.inject({}){ |h,(k,v)| h[k.to_sym]=v; h } })
    end
  end
end

DUMPS = DB.collection('dumps')
USERS = DB.collection('users')