log = File.new("log/memprof.log", "a")
STDOUT.reopen(log)
STDERR.reopen(log)

require 'memprof'
MemprofApp.enable :dump_errors, :raise_errors, :logging
MemprofApp.set :root, File.dirname(__FILE__)
run MemprofApp

