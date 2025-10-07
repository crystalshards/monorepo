require "json"

class Statusline::Input
  include JSON::Serializable

  getter hook_event_name : String?
  getter session_id : String
  getter transcript_path : String
  getter cwd : String
  getter model : Model
  getter workspace : Workspace
  getter version : String
  getter output_style : OutputStyle
  getter cost : Cost
  getter? exceeds_200k_tokens : Bool

  def transcript
    ClaudeCode::Transcript.new(transcript_path) if File.exists?(transcript_path)
  end
end
