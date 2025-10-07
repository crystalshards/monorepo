class ClaudeCode::Transcript::User::Message
  include JSON::Serializable

  getter role : String
  getter content : String | MessageContent
end
