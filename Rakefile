require 'app'
task :update do
  Project.all.each do |project|
    Project.import_from_web(project.id, :import_people => true)
    Story.import_from_web(project.id)
  end  
end

task :import do
  raise "Please specify project_id=project's id" unless ENV['project_id']
  Project.import_from_web(ENV['project_id'], :import_people => true)
  Story.import_from_web(ENV['project_id'])
end

task :cron => :update do
end

task :migrate do
  DataMapper.auto_migrate!
end