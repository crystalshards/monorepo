require "json"
require "yaml"
require "./colorize"
require "./claude_code/transcript"
require "./claude_code/**"
require "./statusline/**"

Colorize.enabled = true

module Statusline
  extend self

  def get_rgb(color : String)
    colors = {
      "black"  => "#111111",
      "white"  => "#ffffff",
      "red"    => "#ff0000",
      "blue"   => "#0000ff",
      "green"  => "#00ff00",
      "yellow" => "#ffff00",
      "purple" => "#8800ff",
      "orange" => "#ff9900",
      "pink"   => "#ff00ff",
      "cyan"   => "#00aaff",
    }
    Colorize::ColorRGB.from_hex(colors[color])
  end

  def build(json : String) : String
    input = Statusline::Input.from_json(json)

    transcript = input.transcript.try(&.reverse)

    model = input.model.display_name
    project_dir = input.workspace.project_dir
    current_dir = input.workspace.current_dir.sub(project_dir, "./")
    lines_added = input.cost.total_lines_added
    lines_removed = input.cost.total_lines_removed
    model = input.model.display_name
    git_branch = get_branch(transcript)
    subagent_type, subagent_color = get_subagent(project_dir, transcript)
    tool_name, tool_description = get_tool(transcript)

    # Build statusline parts
    statusline_parts = [] of String

    # Build agent display with background color
    agent_display = subagent_type.colorize.bold.fore(get_rgb("black")).back(get_rgb(subagent_color)).to_s.sub(";48;", "m\e[48;")
    statusline_parts << "🤖 #{agent_display}"
    statusline_parts << "🌀 #{model}"
    statusline_parts << "🌳 #{File.basename(project_dir)}"
    statusline_parts << "🌿 #{git_branch}"
    statusline_parts << "📁 #{current_dir}"
    # Add lines changed with colors
    if lines_added > 0 || lines_removed > 0
      lines_display = "+#{lines_added}".colorize(:green).to_s + "/" + "-#{lines_removed}".colorize(:red).to_s
      statusline_parts << "🏗️ #{lines_display}"
    end
    statusline_parts << "\n🔧 [#{tool_name}] #{tool_description}".colorize(:dark_gray).to_s if tool_name

    # Build statusline
    statusline = statusline_parts.join(" ")
    statusline.empty? ? "Claude Code" : statusline
  end

  def thread_unresolved?(entry : ClaudeCode::Transcript::Entry::Assistant | ClaudeCode::Transcript::Entry::User, transcript)
    transcript.none? do |other_entry|
      case other_entry
      when ClaudeCode::Transcript::Entry::System
        other_entry.parent_uuid == entry.uuid
      when ClaudeCode::Transcript::Entry::User
        other_entry.parent_uuid == entry.uuid
      when ClaudeCode::Transcript::Entry::Assistant
        other_entry.parent_uuid == entry.uuid
      else
        false
      end
    end
  end

  def thread_unresolved?(entry, transcript)
    false
  end

  def get_tool(entries : ClaudeCode::Transcript)
    entry = entries.find do |entry|
      name, description = get_tool(entry)
      name && thread_unresolved?(entry, entries)
    end
    get_tool(entry)
  end

  def get_tool(entries : Array(ClaudeCode::Transcript::MessageContent))
    get_tool(entries[0]?)
  end

  def get_tool(entry : ClaudeCode::Transcript::MessageContent::ToolUse)
    name = entry.name
    description = entry.input.try(&.["description"]?.try(&.as_s?))
    [name, description]
  end

  def get_tool(entry : ClaudeCode::Transcript::Entry::Assistant)
    get_tool(entry.message.try(&.content))
  end

  def get_tool(entry)
    [nil, nil]
  end

  def get_subagent(project_dir, entries : ClaudeCode::Transcript)
    entry = entries.find do |entry|
          name, color = get_subagent(project_dir, entry)
          name != "claude" && thread_unresolved?(entry, entries)
        end
    get_subagent(project_dir, entry)
  end

  def get_subagent(project_dir, entry : ClaudeCode::Transcript::Entry::Assistant)
    get_subagent(project_dir, entry.message.try(&.content))
  end

  def get_subagent(project_dir, entry : ClaudeCode::Transcript::Entry::User)
    get_subagent(project_dir, entry.message.try(&.content))
  end

  def get_subagent(project_dir, entry : Array(ClaudeCode::Transcript::MessageContent))
    get_subagent(project_dir, entry[0]?)
  end

  def get_subagent(project_dir, entry : ClaudeCode::Transcript::MessageContent::ToolUse)
    subagent_color = "white"
    subagent_type = entry.input["subagent_type"]?.try(&.as_s) || "claude"
    if subagent_type != "claude"
      agent_file = "#{project_dir}/.claude/agents/#{subagent_type}.md"
      if File.exists?(agent_file)
        subagent_color = ClaudeCode::Subagent.new(agent_file).color
      end
    end
    [subagent_type, subagent_color]
  end

  def get_subagent(project_dir, entry)
    ["claude", "white"]
  end

  def get_branch(project_dir, entries : Array(ClaudeCode::Transcript::Entry))
    entry =
      if transcript
        transcript.find do |entry|
          entry.git_branch
        end
      end
    get_branch(project_dir, entry)
  end

  def get_branch(entry : ClaudeCode::Transcript::Entry::Assistant | ClaudeCode::Transcript::Entry::User | ClaudeCode::Transcript::Entry::System)
    entry.git_branch
  end

  def get_branch(entry)
    `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
  end
end
