class Contribute::Show < BrowserAction
  get "/contribute" do
    html Contribute::ShowPage, operation: SubmitContribution.new
  end
end
