require 'rubygems'
require 'bundler'
Bundler.setup

require 'yajl'

raise ArgumentError, "invalid file: #{ARGV[0]}" unless ARGV[0] and File.exists?(ARGV[0])

file = ARGV[0]
basename = File.basename(file, '.json')
refs_file = ARGV[0].sub('.json', '_refs.json')

if true # !File.exists?(refs_file)
  out = File.open(refs_file, 'w')

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

    #print '.'
    puts obj['_id']
    refs.delete obj['_id']

    if refs.any?
      out.puts Yajl.dump :_id => obj['_id'], :refs => refs
    end
  }

  parser.parse(File.open(file,'r'))
  puts 'done!'
  out.close
end

system("mongoimport -h localhost -d memprof_datasets --drop -c #{basename} --file #{file}")
system("mongoimport -h localhost -d memprof_datasets --drop -c #{basename}_refs --file #{refs_file}")

require 'memprof.com'
dump = Memprof::Dump.new(basename)

