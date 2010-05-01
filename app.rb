require 'libxml'
require 'xml'
require 'net/http'
require 'haml'
require 'dm-core'
require 'dm-timestamps'
require 'sinatra/base'

TOKEN = '32aed710efa658397aad59c2d61f84f7'

# DataMapper::Logger.new('log/sinatra.log', :debug)
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/scrums.sql")

module Scrums
  class Application < Sinatra::Base
    configure do
      set :app_file, File.expand_path(File.dirname(__FILE__) + '/app.rb')
      set :public,   File.expand_path(File.dirname(__FILE__) + '/public')
      set :views,    File.expand_path(File.dirname(__FILE__) + '/views')
      disable :run, :reload
    end
    
    helpers do
      def logger
        @@logger ||= Logger.new('log/sinatra.log')
      end
  
      def pivotal(project_id = 77939)
        @pivotal ||= {}
        @pivotal[project_id.to_s] ||= Pivotal.new(project_id, '32aed710efa658397aad59c2d61f84f7')
      end
    end

    get '/dash' do
      @people = Person.all
      haml :dash
    end

    get '/people/:id' do
      @person = Person.get(params[:id])
      haml :person
    end
  end
  
  class Pivotal
    def initialize(project_id, token)
      @server     = Net::HTTP.new('www.pivotaltracker.com')
      @project_id = project_id
      @token      = token
    end

    def project
      get('projects/' + @project_id.to_s)
    end

    def stories
      get("projects/#{@project_id}/stories")
    end

    private
      def get(path)
        response = @server.get "/services/v3/#{path}", { 'X-TrackerToken' => @token }
        response.body        
      end      
  end
end

class Person
  include DataMapper::Resource
    
  property :id,         Integer, :key      => true, :unique => true
  property :name,       String,  :required => true, :unique => true
  property :initials,   String,  :required => true
  property :email,      String,  :required => true, :unique => true
  # timestamps :at
  
  has n, :projects, :through => Resource
  has n, :stories, :child_key => [:owner_id]
  has n, :requested_stories, :model => 'Story', :child_key => [:requester_id]

  
  class << self
    def import_from_response(response, options = {})
      @people = []

      parse_document(response, options) do |initialization_hash|
        unless person = get(initialization_hash[:id])
          person = create! initialization_hash
        else
          person.projects << initialization_hash.delete(:projects).first
          person.update!(initialization_hash)
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
    
  class << self
    def import_from_web(project_id, options = {})
       pivotal = Scrums::Pivotal.new(project_id, TOKEN)

       parse_response pivotal.project, options do |initialization_hash|
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

class Story
  include DataMapper::Resource
    
  property :id,         Integer, :key      => true, :unique => true
  property :name,       String,  :required => true, :length => 255
  property :type,       String
  property :state,      String
  property :url,        String
  property :description,Text
  property :finished_at,DateTime
  # timestamps :at
    
  belongs_to :project
  belongs_to :owner,     'Person', :child_key => [:owner_id], :required  => false
  belongs_to :requester, 'Person', :child_key => [:requester_id]
  
  class << self
    def import_from_web(project_id, options = {})
       pivotal, @stories = Scrums::Pivotal.new(project_id, TOKEN), []

       parse_response pivotal.stories do |initialization_hash|
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
          story_hash[:requester]   = Person.first(:name => story.find('requested_by').first.content)
          story_hash[:owner]       = if story.find('owned_by').first
            Person.first(:name => story.find('owned_by').first.content)
          end
          story_hash[:project]     = Project.get(story.find('project_id').first.content)
          
          yield(story_hash)
        end
      end
  end
end

DataMapper.auto_upgrade!
