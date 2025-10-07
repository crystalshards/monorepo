require "../../../message_content"

class ClaudeCode::Transcript::Assistant::Entry::Message::Message < ClaudeCode::Transcript::Assistant::Entry::Message
  include JSON::Serializable

  getter id : String
  getter role : String
  getter model : String
  getter content : Array(MessageContent)
  getter stop_reason : JSON::Any
  getter stop_sequence : JSON::Any

  class Usage
    include JSON::Serializable

    class CacheCreation
      include JSON::Serializable

      getter ephemeral_5m_input_tokens : Int32
      getter ephemeral_1h_input_tokens : Int32
    end

    getter input_tokens : Int32
    getter cache_creation_input_tokens : Int32
    getter cache_read_input_tokens : Int32
    getter cache_creation : CacheCreation
    getter output_tokens : Int32
    getter service_tier : String
  end
end
