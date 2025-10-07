abstract class ClaudeCode::Transcript::MessageContent
  include JSON::Serializable

  use_json_discriminator("type", {
    tool_use:    ClaudeCode::Transcript::MessageContent::ToolUse,
    text:        ClaudeCode::Transcript::MessageContent::Text,
    tool_result: ClaudeCode::Transcript::MessageContent::ToolResult,
  })

  getter type : String
end
