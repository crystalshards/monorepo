# Only start the app server for integration/request specs
# Worker specs don't need the HTTP server
unless ENV["SKIP_APP_SERVER"]? == "true"
  app_server = AppServer.new

  spawn do
    app_server.listen
  end

  Spec.after_suite do
    app_server.close
  end
end
