class Pricing::Show < BrowserAction
  # The footer has always promised a pricing page. The board charges real
  # money before a posting goes live, so the price has to be readable without
  # first filling in a job form.
  #
  # Every figure comes from the top-level `Pricing` module, which is the one
  # source of truth for the commercial terms. Nothing here restates them.
  get "/pricing" do
    html Pricing::ShowPage
  end
end
