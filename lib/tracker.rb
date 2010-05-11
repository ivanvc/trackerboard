class Tracker
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
