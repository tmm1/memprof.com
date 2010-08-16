require 'setup'
require 'rake'
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
    #puts obj['_id']
    refs.delete obj['_id']

    if refs.any?
      out.puts Yajl.dump :_id => obj['_id'], :refs => refs, :refs_size => refs.size
    end
  }

  parser.parse(File.open(file,'r'))
  puts 'refs completed'
  out.close
end

sh "mongoimport -h localhost -d memprof_datasets --drop -c #{basename}      --file #{file}" rescue nil
sh "mongoimport -h localhost -d memprof_datasets --drop -c #{basename}_refs --file #{refs_file}" rescue nil
sh "mongo localhost/memprof_datasets --eval 'db[\"#{basename}_groups\"].drop()'" rescue nil

puts "creating indexes"
require 'memprof.com'
dump = Memprof::Dump.new(basename)

puts "Import complete!\n\n\n"
