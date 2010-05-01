require 'app'
task :import do
  Project.import_from_web(77939, :import_people => true)
  Story.import_from_web(77939)
end

task :cron => :import do
end

task :migrate do
  DataMapper.auto_migrate!
end