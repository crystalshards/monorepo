class ClaudeCode::Transcript::Entry::Assistant < ClaudeCode::Transcript::Entry
  getter message : ClaudeCode::Transcript::Assistant::Entry::Message
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

  @[JSON::Field(key: "requestId")]
  getter request_id : String?
end
