class ClaudeCode::Transcript::MessageContent::ToolUse < ClaudeCode::Transcript::MessageContent
  getter id : String
  getter name : String
  getter input : JSON::Any
end
