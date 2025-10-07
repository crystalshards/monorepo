class ClaudeCode::Transcript::Entry::Summary < ClaudeCode::Transcript::Entry
  @[JSON::Field(key: "leafUuid")]
  getter leaf_uuid : String?
  getter summary : String?
end
