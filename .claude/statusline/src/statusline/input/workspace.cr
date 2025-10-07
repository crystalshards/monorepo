class Statusline::Input::Workspace
  include JSON::Serializable

  getter current_dir : String
  getter project_dir : String
end
