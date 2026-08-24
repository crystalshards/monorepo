require "./shards"

# Lessons and the runner client before config: config/runner.cr configures
# RunnerClient while the file loads, so the class has to exist by then.
require "./copy"
require "./ansi"
require "./lessons/**"
require "./services/**"

require "../config/server"
require "../config/**"
require "./pages/main_layout"
require "./pages/**"
require "./actions/**"
require "./app_server"
