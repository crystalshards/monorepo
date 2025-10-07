abstract class ClaudeCode::Transcript::Entry
  include JSON::Serializable

  use_json_discriminator "type", {user: User, assistant: Assistant, summary: Summary, system: System}

  getter type : String

  @[JSON::Field(key: "isSidechain")]

  getter? is_sidechain : Bool?
end
