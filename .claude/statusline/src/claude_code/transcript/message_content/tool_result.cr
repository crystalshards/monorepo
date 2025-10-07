class ClaudeCode::Transcript::MessageContent::ToolResult < ClaudeCode::Transcript::MessageContent
  getter tool_use_id : String
  getter content : Array(ClaudeCode::Transcript::MessageContent)
end
