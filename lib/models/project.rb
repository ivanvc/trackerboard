class Project
  include DataMapper::Resource
    
  property :id,               Integer, :key      => true, :unique => true
  property :name,             String,  :required => true
  property :iteration_length, Integer
  property :week_start_day,   String
  property :current_velocity, Integer
  # timestamps :at
  
  has n, :people,  :through => Resource
  has n, :stories

  # belongs_to :account, :required  => false

  def all_people_with_stories
    people_array = []
    people.each do |person|
      people_array << person.to_layout_hash
    end
    people_array
  end
    
  class << self
    
    def import_from_web(project_id, options = {})
       tracker = Tracker.new(project_id, TOKEN)

       parse_response tracker.project, options do |initialization_hash|
         unless @project = get(initialization_hash[:id])
           @project = create! initialization_hash
         else
           @project.update!(initialization_hash)
         end
       end

       @project
     end

     def import_from_response(response)
       parse_response response do |initialization_hash|
         @project = create! initialization_hash
       end

       @project
     end

     private
       def parse_response(response, options = {})
         document = XML::Parser.string(response).parse
         project_hash = {}
         project_hash[:id]               = document.find('//project/id').first.content
         project_hash[:name]             = document.find('//project/name').first.content
         project_hash[:iteration_length] = document.find('//project/iteration_length').first.content
         project_hash[:week_start_day]   = document.find('//project/week_start_day').first.content
         project_hash[:current_velocity] = document.find('//project/current_velocity').first.content

         yield project_hash
         
         if options[:import_people]
           Person.import_from_response\
             document.find('//project/memberships').first.to_s, 
             :project_id => project_hash[:id]
          end
       end
  end
end
