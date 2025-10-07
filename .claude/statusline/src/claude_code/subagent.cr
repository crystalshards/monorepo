require "yaml"
require "front_matter"

class ClaudeCode::Subagent
  include YAML::Serializable

  def self.new(path)
    subagent = nil
    FrontMatter.open(path) do |yaml, _|
      subagent = from_yaml(yaml)
    end
    subagent.not_nil!
  end

  getter name : String
  getter description : String
  getter model : String
  getter color : String
end
