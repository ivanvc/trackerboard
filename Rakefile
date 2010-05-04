require 'app'
task :import do
  Project.import_from_web(77939, :import_people => true)
  Story.import_from_web(77939)
  Project.import_from_web(71754, :import_people => true)
  Story.import_from_web(71754)
  Project.import_from_web(73652, :import_people => true)
  Story.import_from_web(73652)
end

task :cron => :import do
end

task :migrate do
  DataMapper.auto_migrate!
end