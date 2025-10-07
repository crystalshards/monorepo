class ClaudeCode::Transcript::Entry::User < ClaudeCode::Transcript::Entry
  include JSON::Serializable

  getter message : Message?
  getter uuid : String?
  getter timestamp : String?

  @[JSON::Field(key: "parentUuid")]
  getter parent_uuid : String?

  @[JSON::Field(key: "userType")]
  getter user_type : String?

  getter cwd : String?

  @[JSON::Field(key: "sessionId")]
  getter session_id : String?

  getter version : String?

  @[JSON::Field(key: "gitBranch")]
  getter git_branch : String?

  @[JSON::Field(key: "toolUseResult")]
  getter tool_use_result : JSON::Any?

  class Message
    include JSON::Serializable

    getter role : String
    getter content : JSON::Any?
  end
end
