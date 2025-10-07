require "./spec_helper"
require "json"

describe Statusline do
  describe "Input" do
    it "parses JSON correctly" do
      json = <<-JSON
      {
        "session_id": "test-session-123",
        "transcript_path": "/path/to/transcript.jsonl",
        "cwd": "/test/workspace",
        "model": {
          "id": "claude-opus-4-1-20250805",
          "display_name": "Opus 4.1"
        },
        "workspace": {
          "current_dir": "/test/workspace/subdir",
          "project_dir": "/test/workspace"
        },
        "version": "1.0.109",
        "output_style": {
          "name": "default"
        },
        "cost": {
          "total_cost_usd": 0.5,
          "total_duration_ms": 1000,
          "total_api_duration_ms": 500,
          "total_lines_added": 10,
          "total_lines_removed": 5
        },
        "exceeds_200k_tokens": false
      }
      JSON

      input = Statusline::Input.from_json(json)
      
      input.session_id.should eq("test-session-123")
      input.transcript_path.should eq("/path/to/transcript.jsonl")
      input.cwd.should eq("/test/workspace")
      input.model.id.should eq("claude-opus-4-1-20250805")
      input.model.display_name.should eq("Opus 4.1")
      input.workspace.current_dir.should eq("/test/workspace/subdir")
      input.workspace.project_dir.should eq("/test/workspace")
      input.version.should eq("1.0.109")
      input.output_style.name.should eq("default")
      input.cost.total_cost_usd.should eq(0.5_f32)
      input.cost.total_duration_ms.should eq(1000)
      input.cost.total_api_duration_ms.should eq(500)
      input.cost.total_lines_added.should eq(10)
      input.cost.total_lines_removed.should eq(5)
      input.exceeds_200k_tokens.should eq(false)
    end

    it "handles optional hook_event_name" do
      json_with_hook = <<-JSON
      {
        "hook_event_name": "test-hook",
        "session_id": "test-session",
        "transcript_path": "/path/to/transcript.jsonl",
        "cwd": "/test",
        "model": {"id": "test", "display_name": "Test"},
        "workspace": {"current_dir": "/test", "project_dir": "/test"},
        "version": "1.0.0",
        "output_style": {"name": "default"},
        "cost": {
          "total_cost_usd": 0,
          "total_duration_ms": 0,
          "total_api_duration_ms": 0,
          "total_lines_added": 0,
          "total_lines_removed": 0
        },
        "exceeds_200k_tokens": false
      }
      JSON

      input = Statusline::Input.from_json(json_with_hook)
      input.hook_event_name.should eq("test-hook")
    end
  end

  describe "Input::Cost" do
    it "parses cost data correctly" do
      json = <<-JSON
      {
        "total_cost_usd": 1.25,
        "total_duration_ms": 5000,
        "total_api_duration_ms": 2500,
        "total_lines_added": 100,
        "total_lines_removed": 50
      }
      JSON

      cost = Statusline::Input::Cost.from_json(json)
      
      cost.total_cost_usd.should eq(1.25_f32)
      cost.total_duration_ms.should eq(5000)
      cost.total_api_duration_ms.should eq(2500)
      cost.total_lines_added.should eq(100)
      cost.total_lines_removed.should eq(50)
    end
  end

  describe "Input::Model" do
    it "parses model data correctly" do
      json = <<-JSON
      {
        "id": "claude-opus-4-1-20250805",
        "display_name": "Opus 4.1"
      }
      JSON

      model = Statusline::Input::Model.from_json(json)
      
      model.id.should eq("claude-opus-4-1-20250805")
      model.display_name.should eq("Opus 4.1")
    end
  end

  describe "Input::OutputStyle" do
    it "parses output style data correctly" do
      json = <<-JSON
      {
        "name": "custom-style"
      }
      JSON

      style = Statusline::Input::OutputStyle.from_json(json)
      
      style.name.should eq("custom-style")
    end
  end

  describe "Input::Workspace" do
    it "parses workspace data correctly" do
      json = <<-JSON
      {
        "current_dir": "/Users/test/project/subdir",
        "project_dir": "/Users/test/project"
      }
      JSON

      workspace = Statusline::Input::Workspace.from_json(json)
      
      workspace.current_dir.should eq("/Users/test/project/subdir")
      workspace.project_dir.should eq("/Users/test/project")
    end
  end

  describe "Statusline generation" do
    it "generates statusline with basic information" do
      json = <<-JSON
      {
        "session_id": "test-session",
        "transcript_path": "/nonexistent/transcript.jsonl",
        "cwd": "/test/workspace",
        "model": {
          "id": "claude-opus-4-1-20250805",
          "display_name": "Opus 4.1"
        },
        "workspace": {
          "current_dir": "/test/workspace/subdir",
          "project_dir": "/test/workspace"
        },
        "version": "1.0.109",
        "output_style": {
          "name": "default"
        },
        "cost": {
          "total_cost_usd": 0,
          "total_duration_ms": 0,
          "total_api_duration_ms": 0,
          "total_lines_added": 0,
          "total_lines_removed": 0
        },
        "exceeds_200k_tokens": false
      }
      JSON

      input = Statusline::Input.from_json(json)
      
      # Test that we can extract the values we need for statusline
      input.model.display_name.should eq("Opus 4.1")
      input.workspace.project_dir.should eq("/test/workspace")
      input.workspace.current_dir.should eq("/test/workspace/subdir")
      input.cost.total_lines_added.should eq(0)
      input.cost.total_lines_removed.should eq(0)
    end

    it "handles lines added and removed" do
      json = <<-JSON
      {
        "session_id": "test-session",
        "transcript_path": "/nonexistent/transcript.jsonl",
        "cwd": "/test/workspace",
        "model": {
          "id": "claude-opus-4-1-20250805",
          "display_name": "Opus 4.1"
        },
        "workspace": {
          "current_dir": "/test/workspace",
          "project_dir": "/test/workspace"
        },
        "version": "1.0.109",
        "output_style": {
          "name": "default"
        },
        "cost": {
          "total_cost_usd": 0,
          "total_duration_ms": 0,
          "total_api_duration_ms": 0,
          "total_lines_added": 50,
          "total_lines_removed": 25
        },
        "exceeds_200k_tokens": false
      }
      JSON

      input = Statusline::Input.from_json(json)
      
      input.cost.total_lines_added.should eq(50)
      input.cost.total_lines_removed.should eq(25)
    end

    it "handles relative path calculation" do
      json = <<-JSON
      {
        "session_id": "test-session",
        "transcript_path": "/nonexistent/transcript.jsonl",
        "cwd": "/test/workspace",
        "model": {
          "id": "claude-opus-4-1-20250805",
          "display_name": "Opus 4.1"
        },
        "workspace": {
          "current_dir": "/test/workspace/deep/nested/dir",
          "project_dir": "/test/workspace"
        },
        "version": "1.0.109",
        "output_style": {
          "name": "default"
        },
        "cost": {
          "total_cost_usd": 0,
          "total_duration_ms": 0,
          "total_api_duration_ms": 0,
          "total_lines_added": 0,
          "total_lines_removed": 0
        },
        "exceeds_200k_tokens": false
      }
      JSON

      input = Statusline::Input.from_json(json)
      
      # Simulate the relative path calculation from the main script
      relative_dir = input.workspace.current_dir.sub(input.workspace.project_dir, "./")
      relative_dir.should eq(".//deep/nested/dir")
    end
  end
end
