require 'db'
require 'ftools'

def cleanup(basename, storage_name=nil)
  File.delete(storage_name) if storage_name
  File.delete("#{basename}.json.gz") if File.exists?("#{basename}.json.gz")
  File.delete("#{basename}.json") if File.exists?("#{basename}.json")
  File.delete("#{basename}_refs.json") if File.exists?("#{basename}_refs.json")
end

def process_dump(dump)
  dump_id = dump['_id'].to_s

  basename = File.expand_path("../dumps/#{dump_id}", __FILE__)
  storage_name = File.expand_path("../stored_dumps/#{dump_id}.json.gz", __FILE__)

  File.copy("#{basename}.json.gz", storage_name)

  puts "gunzip -f #{basename}.json.gz"
  puts `gunzip -f #{basename}.json.gz`
  if $?.exitstatus == 0
    puts "ruby import_json.rb #{basename}.json"
    puts `ruby import_json.rb #{basename}.json`
    if $?.exitstatus == 0
      DUMPS.save(dump.merge('status' => 'imported'))
      cleanup(basename)
    else
      DUMPS.save(dump.merge('status' => 'failed'))
      cleanup(basename, storage_name)
    end
  else
    DUMPS.save(dump.merge('status' => 'failed'))
    cleanup(basename, storage_name)
  end
end

loop do
  if dumps = DUMPS.find(:status => 'pending')
    dumps.each {|d| process_dump(d)}
  end

  sleep 1
end
