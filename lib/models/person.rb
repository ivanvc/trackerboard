class Person
  include DataMapper::Resource
    
  property :id,       Integer, :key      => true, :unique => true
  property :name,     String,  :required => true
  property :initials, String,  :required => true
  property :email,    String,  :required => true, :unique => true
  property :visible,  Boolean, :default  => true
  # timestamps :at
  
  has n, :projects, :through => Resource
  has n, :stories, :child_key => [:owner_id]
  has n, :requested_stories, :model => 'Story', :child_key => [:requester_id]

  def to_layout_hash
    person_hash = { 
      :person      => self,
      :started     => stories.all(:state => 'started'),
      :finished    => stories.all(:state => 'finished'),
      :delivered   => stories.all(:state => 'delivered'),
      :accepted    => stories.all(:state => 'accepted'),
      :rejected    => stories.all(:state => 'rejected'),
      :unstarted   => stories.all(:state => 'unstarted'),
      :unscheduled => stories.all(:state => 'unscheduled') }
    person_hash[:empty] = person_hash[:started].empty? && person_hash[:finished].empty? && person_hash[:delivered].empty?
    person_hash[:completely_empty] = person_hash[:empty] && person_hash[:accepted].empty? && person_hash[:delivered].empty? && person_hash[:rejected].empty? && person_hash[:unstarted].empty? && person_hash[:unscheduled].empty?
    person_hash
  end
  
  class << self
    
    def all_with_stories
      people_array = []
      all.each do |person|
        people_array << person.to_layout_hash
      end
      people_array
    end
    
    def import_from_response(response, options = {})
      @people = []

      parse_document(response, options) do |initialization_hash|
        person = first(:email => initialization_hash[:email])
        unless person
          person = create initialization_hash
        else
          person.projects << initialization_hash.delete(:projects).first
          person.update(initialization_hash)
          person.save
        end
        @people << person
      end
      @people
    end

    private
      def parse_document(response, options = {})
        document = XML::Parser.string(response).parse
        
        document.find('//memberships/membership').each do |member|
          person_hash = {}
          person_hash[:id]       = member.find('id').first.content
          person_hash[:email]    = member.find('person/email').first.content
          person_hash[:name]     = member.find('person/name').first.content
          person_hash[:initials] = member.find('person/initials').first.content
          if options[:project_id]
            person_hash[:projects] = [Project.get(options[:project_id])]
          end

          yield(person_hash)        
        end
      end    
  end
end
