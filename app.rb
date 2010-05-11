require 'libxml'
require 'xml'
require 'net/http'
require 'haml'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'sinatra/base'

require 'lib/tracker'
Dir[Dir.pwd + '/lib/models/*'].each { |file| require file }

TOKEN = if ENV['TOKEN']
  ENV['TOKEN']
else
  YAML.load(File.read 'token.yml')['token'] rescue ''
end

DataMapper::Logger.new('log/sinatra.log', ENV['RACK_ENV'] == 'production' ? :info : :debug)
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/scrums.sql")
DataMapper.auto_upgrade!

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
        @@logger ||= Logger.new('log/app.log')
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
    
  end  
end

# class Account
#   include DataMapper::Resource
#   # Add authorization
#   property :id,    Serial
#   property :token, String, :required => true
#   
#   has n, :projects
#   
# end

