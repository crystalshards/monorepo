class Jobs::New < BrowserAction
  get "/jobs/new" do
    operation = SaveJob.new

    html Jobs::NewPage, operation: operation
  end
end
