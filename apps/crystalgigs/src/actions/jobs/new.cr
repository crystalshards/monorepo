class Jobs::New < BrowserAction
  get "/jobs/new" do
    html Jobs::NewPage, operation: SaveJob.new
  end
end
