class Contributions::Create < BrowserAction
  post "/contributions" do
    SubmitContribution.create(params) do |operation, contribution|
      if contribution
        redirect to: Contributions::Thanks
      else
        flash.failure = "We could not accept that submission. Check the fields below."
        html Contribute::ShowPage, operation: operation
      end
    end
  end
end
