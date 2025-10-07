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
- 🔧 Shows tool calls with their inputs (color-coded in yellow)
- ✅ Indicates tool completion with truncated output
- ❌ Highlights errors in red
- 👤 Shows user messages
- 🎨 Color-coded output for easy reading

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

```
🚀 Claude initialized
   Model: claude-sonnet-4-5-20250929
   Session: 6d4dcb77-ada8-4eba-b092-5393bc1a72f7

💭 I'll search for today's news and write it to a file.

🔧 Tool: WebSearch
   Input: {"query": "latest news October 7 2025"}

💭

🔧 Tool: Write
   Input: {"file_path": "news.txt", "content": "..."}

💭 File written to news.txt
```

## Technical Details

- Written in Crystal for performance
- Handles multi-line JSON objects correctly
- Properly escapes strings to avoid false brace matching
- Supports all Claude streaming event types
- Uses colorize for terminal colors
