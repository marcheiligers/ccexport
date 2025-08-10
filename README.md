# Claude Code Conversation Exporter (Ruby)

A Ruby tool to export Claude Code conversations to GitHub-flavored Markdown format, styled to look similar to Claude Desktop conversations for easy reading.

## Features

### Core Functionality
- Exports complete Claude Code conversations including prompts, responses, and tool calls
- GitHub-flavored Markdown output optimized for readability
- Automatically discovers Claude Code session files
- Claude Desktop-inspired formatting with user/assistant message indicators
- Comprehensive RSpec test suite with 70 tests
- HTML Preview Generation: Convert Markdown to HTML with GitHub styling

### Enhanced Tool Formatting
- **Write Tool**: Shows relative file paths in summary with syntax-highlighted code blocks
- **Bash Tool**: Displays command descriptions in summary with bash syntax highlighting  
- **Edit Tool**: Before/After sections showing old and new code with syntax highlighting
- **TodoWrite Tool**: Emoji-enhanced task lists (✅ completed, 🔄 in progress, ⏳ pending)

### Advanced Features
- **Universal Path Relativization**: All absolute project paths converted to relative paths
- **Smart Tool Pairing**: Automatically pairs tool_use with corresponding tool_result messages
- **Syntax Highlighting**: Supports Ruby, JavaScript, Python, TypeScript, JSON, Markdown, YAML, Bash
- **Robust Message Processing**: Handles edge cases like tool-only messages and system filtering
- **Date Filtering**: Filter conversations by date range or today only (timezone-aware)
- **Multiple Session Combining**: Automatically combines multiple sessions into single chronologically ordered output
- **Thinking Message Support**: Displays thinking content with blockquotes and special emoji (🤖💭)

## Installation

1. Clone this repository
2. Install dependencies: `bundle install`

## Usage

### Simple Usage

Run the exporter in any directory where you've used Claude Code:

```ruby
require_relative 'lib/claude_conversation_exporter'

ClaudeConversationExporter.export
```

### Custom Usage

```ruby
require_relative 'lib/claude_conversation_exporter'

# Export from specific project path to custom output directory
exporter = ClaudeConversationExporter.new('/path/to/project', 'my-conversations')
result = exporter.export

puts "Exported #{result[:sessions_exported]} conversations"
puts "Total messages: #{result[:total_messages]}"
```

### Command Line Usage

```bash
# Basic usage - export all conversations
./bin/ccexport

# Filter by date range
./bin/ccexport --from 2024-01-01 --to 2024-01-31

# Filter using timestamp format (copy from --timestamps output)
./bin/ccexport --from "August 09, 2025 at 06:03:43 PM"

# Export only today's conversations
./bin/ccexport --today

# Custom output directory
./bin/ccexport --out /path/to/output

# Output to specific file (creates matching .html for preview)
./bin/ccexport --out myconversation.md --preview

# Show timestamps with each message
./bin/ccexport --timestamps

# Generate HTML preview and open in browser
./bin/ccexport --preview

# Generate HTML preview without opening browser
./bin/ccexport --preview --no-open

# Combine multiple options
./bin/ccexport --from 2024-01-15 --out ./my-exports --timestamps --preview
```

#### Command Line Options

- `--from DATE`: Filter messages from this date (YYYY-MM-DD or timestamp format from --timestamps output)
- `--to DATE`: Filter messages to this date (YYYY-MM-DD or timestamp format from --timestamps output)
- `--today`: Filter messages from today only (in your local timezone)
- `--out PATH`: Custom output directory or specific file path (supports relative paths, use .md extension for specific file)
- `--timestamps`: Show precise timestamps with each message for easy reference
- `--preview`: Generate HTML preview and open in browser automatically
- `--no-open`: Generate HTML preview without opening in browser (requires --preview)
- `--help`: Show usage information

## Output Format

The exporter creates Markdown files with:

- **Session metadata**: Session ID, timestamps (in local timezone), message counts
- **User messages**: Marked with 👤 User
- **Assistant messages**: Marked with 🤖 Assistant  
- **Thinking messages**: Marked with 🤖💭 Assistant with blockquoted content
- **Tool use**: Marked with 🤖🔧 Assistant with collapsible sections and syntax highlighting
- **Multiple sessions**: Combined into single file with clear session separators
- **Relative paths**: All project paths converted to relative format
- **Clean formatting**: Optimized for GitHub and other Markdown viewers

### Example Output

#### Basic Conversation
```markdown
# Claude Code Conversation

**Session:** `20240101-120000-example-session`  
**Started:** January 1, 2024 at 12:00 PM
**Last activity:** January 1, 2024 at 12:30 PM
**Messages:** 4 (2 user, 2 assistant)

---

## 👤 User

Can you create a simple Ruby script for me?

## 🤖 Assistant

I'll create a Ruby script for you.
```

#### Enhanced Tool Formatting

**Write Tool:**
```markdown
## 🤖🔧 Assistant
<details>
<summary>Write lib/hello.rb</summary>

```ruby
#!/usr/bin/env ruby

puts "Hello, World!"
```
</details>

<details>
<summary>Tool Result</summary>

```
File created successfully at: lib/hello.rb
```
</details>
```

**Edit Tool:**
```markdown
## 🤖🔧 Assistant
<details>
<summary>Edit lib/hello.rb</summary>

**Before:**
```ruby
puts "Hello, World!"
```

**After:**
```ruby
puts "Hello, Ruby!"
```
</details>
```

**Bash Tool:**
```markdown
## 🤖🔧 Assistant
<details>
<summary>Bash: Run the Ruby script</summary>

```bash
ruby lib/hello.rb
```
</details>
```

**Thinking Messages:**
```markdown
## 🤖💭 Assistant

I need to analyze this request carefully.

> The user is asking for a Ruby script
> I should create something simple and clear
> Let me start with a basic Hello World example

Based on your request, I'll create a simple Ruby script.
```

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## Credits

This Ruby implementation is based on the excellent [claude-code-exporter](https://github.com/developerisnow/claude-code-exporter) JavaScript project by developerisnow. The original project provides the foundation for understanding Claude Code's session storage format and export patterns.

The GitHub-flavored Markdown formatting features were implemented with reference to the [GitHub Markdown Cheatsheet](https://ml-run.github.io/github_markdown_cheatsheet.html), particularly the collapsed sections functionality.

### Key Enhancements in This Ruby Version
- **Enhanced tool formatting**: Specialized formatting for Write, Edit, and Bash tools
- **Syntax highlighting**: Automatic language detection and code block formatting
- **Path relativization**: Clean, portable output with relative paths
- **Advanced tool pairing**: Smart matching of tool_use with tool_result messages
- **Integrated HTML Preview**: Generate and open HTML previews with GitHub styling
- **Comprehensive testing**: 70 RSpec tests covering all functionality
- **Ruby-idiomatic**: Clean, maintainable Ruby code structure

## Requirements

- Ruby 2.7+
- Claude Code installed and configured
- RSpec (for testing)
- cmark-gfm (for HTML preview generation): `brew install cmark-gfm`

## License

MIT License - feel free to use and modify as needed.