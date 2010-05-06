require 'libxml'
require 'xml'
require 'net/http'
require 'haml'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'sinatra/base'
require 'openid'
require 'openid/store/filesystem'
require 'openid_dm_store'

TOKEN = 'ef62046fe43cfb2a4adb434f7774767b'

DataMapper::Logger.new('log/sinatra.log', :debug)
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/scrums.sql")

OpenIDDataMapper::Association.auto_migrate!
OpenIDDataMapper::Nonce.auto_migrate!
 
module Scrums
  class Application < Sinatra::Base
    configure do
      set :app_file, File.expand_path(File.dirname(__FILE__) + '/app.rb')
      set :public,   File.expand_path(File.dirname(__FILE__) + '/public')
      set :views,    File.expand_path(File.dirname(__FILE__) + '/views')
      enable :sessions
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
    
    before do
      @projects = Project.all
    end

    get '/' do
      @projects = nil
      haml :index
    end

    get '/dash' do
      @people   = Person.all_with_stories
      haml :dash
    end

    get '/people/:id' do
      @person = Person.get(params[:id]).to_layout_hash
      haml :person
    end
    
    get '/projects/:id' do
      @project = Project.get(params[:id])
      @people  = @project.all_people_with_stories
      haml :dash
    end
    
    # OpenID
    def openid_consumer
      @openid_consumer ||= OpenID::Consumer.new(session, OpenIDDataMapper::DataMapperStore.new)  
    end

    def root_url
      request.url.match(/(^.*\/{2}[^\/]*)/)[1]
    end

    def logged_in?
      !session[:account_id].nil?
    end

    get '/logout' do
      session[:user] = nil
      redirect '/'
    end

    # Send everything else to the super app
    get '/login' do    
      haml :login
    end

    post '/login' do
      openid = params[:openid_identifier]
      begin
        oidreq = openid_consumer.begin(openid)
      rescue OpenID::DiscoveryFailure => why
        "Sorry, we couldn't find your identifier '#{openid}'"
      else
        # oidreq.add_extension_arg('sreg','required','nickname')
        # oidreq.add_extension_arg('sreg','optional','fullname, email')
        redirect oidreq.redirect_url(root_url, root_url + "/login/complete")
      end
    end

    post '/accounts' do
      logger.info "PARAMS: #{params['account']}"
      account = Account.create!(params['account'])
      session[:account_id] = account['id']
      redirect '/dash'
    end

    get '/login/complete' do
      oidresp = openid_consumer.complete(params, request.url)

      case oidresp.status
        when OpenID::Consumer::FAILURE
          "Sorry, we could not authenticate you with the identifier '{openid}'."
        when OpenID::Consumer::SETUP_NEEDED
          "Immediate request failed - Setup Needed"
        when OpenID::Consumer::CANCEL
          "Login cancelled."
        when OpenID::Consumer::SUCCESS
          # Access additional informations:
          # puts params['openid.sreg.nickname']
          # puts params['openid.sreg.fullname']
          @identifier = oidresp.display_identifier
          if account = Account.first(:openid => @identifier)
            session[:account_id] = account['id']
            redirect '/dash'
          else
            haml :new_account
          end
      end
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
        puts "Updating #{initialization_hash.inspect}"
        person = first(:email => initialization_hash[:email])
        unless person
          puts "Person: #{person.inspect}"
          person = create initialization_hash
        else
          person.projects << initialization_hash.delete(:projects).first
          puts "Updating #{person.projects.inspect}"
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

class Project
  include DataMapper::Resource
    
  property :id,               Integer, :key      => true, :unique => true
  property :name,             String,  :required => true
  property :iteration_length, Integer
  property :week_start_day,   String
  property :current_velocity, Integer
  # timestamps :at
  
  has n, :people,   :through => Resource
  has n, :stories
  has n, :accounts, :through => Resource

  def all_people_with_stories
    people_array = []
    people.each do |person|
      people_array << person.to_layout_hash
    end
    people_array
  end
    
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

class Account
  include DataMapper::Resource
  # Add authorization
  property :id,     Serial
  property :token,  String, :required => true
  property :openid, String, :length   => 255, :unique => true
  
  has n, :projects, :through => Resource
end

DataMapper.auto_upgrade!