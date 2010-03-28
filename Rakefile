desc "db console"
task :db do
  sh 'irb -r db.rb'
end

task :start do
  if File.exists? 'pid/thin.pid'
    puts 'Thin already started'
  else
    sh 'thin start -a 127.0.0.1 -p 7006 -l log/thin.log -P pid/thin.pid -t 1200 -d'
  end
end

task :stop do
  sh 'thin stop -P pid/thin.pid' if File.exists? 'pid/thin.pid'
end
