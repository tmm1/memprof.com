require 'rubygems'
require 'yajl'

raise ArgumentError, "invalid file: #{ARGV[0]}" unless ARGV[0] and File.exists?(ARGV[0])

out = File.open(ARGV[0].sub('.json', '_refs.json'), 'w')
basename = File.basename(out.path, '.json')

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

  print '.'
  refs.delete obj['_id']

  if refs.any?
    out.puts Yajl.dump :_id => obj['_id'], :refs => refs
  end
}

parser.parse(File.open(ARGV[0],'r'))
puts 'done!'
out.close

system("mongoimport -h localhost -d memprof_datasets --drop -c #{basename} --file #{out.path}")
system("mongoimport -h localhost -d memprof_datasets --drop -c #{basename.gsub(/_refs/,'')} --file #{out.path.gsub(/_refs/,'')}")
