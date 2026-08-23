# How the web app reaches the sandbox. The URL is a deployment fact, not a
# business fact, so it lives in the environment; but it has a development
# default on purpose, because a fresh checkout should be able to run the app
# and see the console up with nothing but `crystal run`. In production there
# is deliberately no default: a revision that pointed itself at a localhost
# that does not exist would look deployed and answer every submission with
# "the sandbox is not answering", which is a misconfiguration worth refusing
# to boot for.
RunnerClient.configure do |settings|
  if LuckyEnv.production?
    settings.url = runner_url_from_env
  else
    settings.url = ENV.fetch("RUNNER_URL", "http://localhost:9292")
  end
end

private def runner_url_from_env
  ENV["RUNNER_URL"]? || raise_missing_runner_url
end

private def raise_missing_runner_url
  puts "Please set the RUNNER_URL environment variable to the sandbox's base URL, " \
       "for example http://trycrystal-runner-internal:9292. There is no default " \
       "in production.".colorize.red
  exit(1)
end
