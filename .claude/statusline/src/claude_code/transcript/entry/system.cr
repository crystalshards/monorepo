class ClaudeCode::Transcript::Entry::System < ClaudeCode::Transcript::Entry
  include JSON::Serializable

  getter uuid : String?
  getter timestamp : String?

  @[JSON::Field(key: "parentUuid")]
  getter parent_uuid : String?

  @[JSON::Field(key: "logicalParentUuid")]
  getter logical_parent_uuid : String?

  @[JSON::Field(key: "userType")]
  getter user_type : String?

  getter cwd : String?

  @[JSON::Field(key: "sessionId")]
  getter session_id : String?

  getter version : String?

  @[JSON::Field(key: "gitBranch")]
  getter git_branch : String?

  getter content : String | MessageContent
end
