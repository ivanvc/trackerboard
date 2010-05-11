class Story
  include DataMapper::Resource
    
  property :id,         Integer, :key      => true, :unique => true
  property :name,       String,  :required => true, :length => 255
  property :type,       String
  property :state,      String
  property :url,        String,  :length   => 80
  property :description,Text
  property :finished_at,DateTime
  # timestamps :at
    
  belongs_to :project
  belongs_to :owner,     'Person', :child_key => [:owner_id], :required  => false
  belongs_to :requester, 'Person', :child_key => [:requester_id]
  
  def to_markup
    "<img src=\"/images/#{type}.png\" alt=\"#{type}\" /> <a href=\"#{url}\">#{name}</a>"
  end
  
  class << self
    def import_from_web(project_id, options = {})
       tracker, @stories = Tracker.new(project_id, TOKEN), []

       parse_response tracker.stories do |initialization_hash|
         unless story = get(initialization_hash[:id])
           story = create! initialization_hash
         else
           story.update!(initialization_hash)
         end
         @stories << story
       end

       @stories
     end
    
    private
      def parse_response(response)
        document = XML::Parser.string(response).parse

        document.find('//stories/story').each do |story|
          story_hash               = {}
          story_hash[:id]          = story.find('id').first.content
          story_hash[:type]        = story.find('story_type').first.content
          story_hash[:url]         = story.find('url').first.content
          story_hash[:state]       = story.find('current_state').first.content
          story_hash[:description] = story.find('description').first.content
          story_hash[:name]        = story.find('name').first.content
          story_hash[:project]     = Project.get(story.find('project_id').first.content)
          story_hash[:requester]   = story_hash[:project].people.first\
            :name => story.find('requested_by').first.content
          story_hash[:owner]       = if story.find('owned_by').first
            story_hash[:project].people.first(:name => story.find('owned_by').first.content)
          end
          
          yield(story_hash)
        end
      end
  end
end
