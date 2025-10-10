# Claude Stream Renderer

A human-readable renderer for Claude's streaming JSON output.

## Usage

Pipe the streaming JSON output from Claude CLI directly to the renderer:

```bash
claude --dangerously-skip-permissions --print --include-partial-messages --output-format=stream-json --verbose "your message" | ./tools/claude-render
```

Or process a saved log file:

```bash
cat log.txt | ./tools/claude-render
```

## Features

- 🚀 Shows session initialization with model info
- 💭 Displays Claude's thinking in real-time
- ▶ Shows tool calls with smart formatting (no raw JSON!)
- ✓ Indicates tool completion with truncated output
- ✗ Highlights errors in red
- 👤 Shows user messages
- 🎨 Color-coded output for easy reading
- 📊 Deep visual hierarchy with indentation
- 🔍 Smart tool input parsing for common tools (Bash, Read, Edit, Write, Grep, Glob, TodoWrite, etc.)
- 📏 Automatic truncation for long outputs (shows first 8 lines + summary)

## Installation

The repository includes both:

- **claude-stream-renderer.cr** - Crystal source (run with `crystal run`)
- **claude-stream-renderer** - Compiled binary (faster)
- **claude-render** - Wrapper script that uses compiled version if available

### Compile from source

```bash
cd tools
crystal build claude-stream-renderer.cr -o claude-stream-renderer --release
```

## Output Format

The renderer parses Claude's stream-json format and displays:

1. **System initialization**: Model, session ID, available tools
2. **Assistant messages**: Text streamed in real-time
3. **Tool usage**: Tool name and formatted input parameters
4. **Tool results**: Success/error status with output (truncated if long)
5. **User messages**: Prompts and follow-ups

## Example Output

### Basic Tool Call (Bash)
```
🚀 Claude initialized
   Model: claude-sonnet-4-5-20250929
   Session: 6d4dcb77-ada8-4eba-b092-5393bc1a72f7

💭
▶ Tool: Bash

  Command: gh issue create --title 'Test Issue' --body 'Test body'
  Purpose: Create a test GitHub issue

  ✓ Success
    Created issue #123
    URL: https://github.com/org/repo/issues/123

I created the GitHub issue successfully.
```

### File Editing
```
▶ Tool: Edit

  File: /workspace/monorepo/apps/crystalshards/src/actions/api/shards/index.cr
  Mode: Replace First
  Old: "shards = ShardQuery.new.limit(100)"
  New: "shards = ShardQuery.new
      .search(params.get?("..." (162 chars)

  ✓ Success
    File updated successfully
```

### Todo Management
```
▶ Tool: TodoWrite

  Tasks:
    ✓ Add search functionality to API
    ✓ Add pagination support
    ▶ Add tests for search and pagination
    ○ Update API documentation

  ✓ Success
    Todos have been modified successfully
```

### Error Handling
```
▶ Tool: Bash

  Command: kubectl get pods -n nonexistent
  Purpose: Check pods in namespace

  ✗ Error
    Error from server (NotFound): namespaces "nonexistent" not found
```

### Long Output Truncation
```
▶ Tool: Grep

  Pattern: IndexShardWorker
  Path: /workspace/monorepo/apps/crystalshards/src
  Filter: **/*.cr

  ✓ Success
    /workspace/monorepo/apps/crystalshards/src/workers/index_shard_worker.cr
    /workspace/monorepo/apps/crystalshards/src/workers/build_docs_worker.cr
    /workspace/monorepo/apps/crystalshards/src/workers/update_dependencies_worker.cr
    /workspace/monorepo/apps/crystalshards/src/jobs/process_shard_job.cr
    /workspace/monorepo/apps/crystalshards/src/jobs/build_documentation_job.cr
    /workspace/monorepo/apps/crystalshards/src/jobs/update_deps_job.cr
    /workspace/monorepo/apps/crystalshards/src/models/shard.cr
    /workspace/monorepo/apps/crystalshards/src/models/shard_version.cr
    ... (5 more lines)
```

## Technical Details

- Written in Crystal for performance
- Handles multi-line JSON objects correctly
- Properly escapes strings to avoid false brace matching
- Supports all Claude streaming event types
- Uses colorize for terminal colors
