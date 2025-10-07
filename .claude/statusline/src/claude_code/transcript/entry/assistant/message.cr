abstract class ClaudeCode::Transcript::Assistant::Entry::Message
  include JSON::Serializable

  use_json_discriminator("type", {message: Message})

  getter type : String
end
