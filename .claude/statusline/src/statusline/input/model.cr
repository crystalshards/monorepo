require "json"

class Statusline::Input::Model
  include JSON::Serializable

  getter id : String
  getter display_name : String
end
