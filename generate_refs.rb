require 'rubygems'
require 'yajl'

raise ArgumentError, "invalid file: #{ARGV[0]}" unless ARGV[0] and File.exists?(ARGV[0])

out = File.open(ARGV[0].sub('.json', '_refs.json'), 'w')

parser = Yajl::Parser.new :check_utf8 => false
parser.on_parse_complete = proc{ |obj|
  refs = []

  obj.each do |k,v|
    case v
    when Array, Hash
      v.each do |kk,vv|
        refs << kk if kk.is_a?(String) and kk =~ /^0x/
        refs << vv if vv.is_a?(String) and vv =~ /^0x/
      end
    when String
      if v =~ /^0x/
        refs << v
      end
    end
  end

  refs.delete obj['_id']

  if refs.any?
    out.puts Yajl.dump :_id => obj['_id'], :refs => refs
  end
}

parser.parse(File.open(ARGV[0],'r'))
out.close

__END__

require 'rubygems'
require 'mongo'

conn = Mongo::Connection.new
coll = conn.db('memprof').collection('bundler3')

p Time.now
coll.db.eval('function(name){
  var refs_table = db[name + "_refs"];
  db[name].find().forEach(function(){
    var refs = [];

    for (key in this) {
      var val = this[key];

      if (typeof val == "string") {
        if (val.match(/^0x/))
          refs.push(val);

      } else if (val instanceof Array) {
        for (var i=0; i < val.length; i++) {
          if (typeof val[i] == "string" && val[i].match(/^0x/))
            refs.push(val[i]);
        }

      } else if (typeof val == "object") {
        for (nkey in val) {
          var nval = val[nkey];
          if (typeof nkey == "string" && nkey.match(/^0x/))
            refs.push(nkey);
          if (typeof nval == "string" && nval.match(/^0x/))
            refs.push(nval);
        }
      }
    }

    if (refs.length > 0) {
      refs_table.save({_id: this._id, refs: refs});
    }
  });
}', 'bundler3')
p Time.now
