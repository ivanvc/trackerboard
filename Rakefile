require 'app'
task :import do
  Project.all.each do |project|
    Project.import_from_web(project.id, :import_people => true)
    Story.import_from_web(project.id)
  end  
end

task :cron => :import do
end

task :migrate do
  DataMapper.auto_migrate!
end