# Runtime configuration for machine drafting.
#
# Both values are read from the environment and neither has a default. With
# them unset the generator is inert: it reports which variables are missing and
# writes nothing. Nothing here falls back to a placeholder credential or a
# guessed model identifier, because a wrong model name produces a runtime 404
# that reads like an outage instead of like a misconfiguration.
#
#   BITS_MODEL_API_KEY   model API credential
#   BITS_MODEL           model identifier, for example a Claude Opus 5 model id
#   BITS_MODEL_API_BASE  optional, defaults to the Anthropic messages endpoint
#
# Ingestion of the Crystal blog feed and the contribution form need no
# configuration and work with none of these set.
DraftGenerator.configure do |settings|
  settings.api_key = ENV["BITS_MODEL_API_KEY"]?.presence
  settings.model = ENV["BITS_MODEL"]?.presence

  if api_base = ENV["BITS_MODEL_API_BASE"]?.presence
    settings.api_base = api_base
  end
end

# Who may approve content.
#
#   BITS_EDITOR_USER      editor username
#   BITS_EDITOR_PASSWORD  editor password
#
# No defaults, deliberately. With either unset the moderation routes answer
# 503 and say which variable is missing, so an unconfigured deployment cannot
# publish anything rather than publishing with a known-to-everyone password.
EditorCredentials.configure do |settings|
  settings.username = ENV["BITS_EDITOR_USER"]?.presence
  settings.password = ENV["BITS_EDITOR_PASSWORD"]?.presence
end
