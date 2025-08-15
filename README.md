# Claude Code Conversation Exporter (Ruby)

A Ruby tool to export Claude Code conversations to GitHub-flavored Markdown format, styled to look similar to Claude Desktop conversations for easy reading.

> **⚠️ Security Notice**: This tool includes automatic secret detection, but **always review your exports before sharing**. You are responsible for ensuring no sensitive information is included in shared conversation exports.

## Features

### Core Functionality
- Exports complete Claude Code conversations including prompts, responses, and tool calls
- GitHub-flavored Markdown output optimized for readability
- Automatically discovers Claude Code session files
- Claude Desktop-inspired formatting with user/assistant message indicators
- Comprehensive RSpec test suite with 96 tests
- HTML Preview Generation: Convert Markdown to HTML with GitHub styling and embedded syntax highlighting

### Enhanced Tool Formatting
- **Write Tool**: Shows relative file paths in summary with syntax-highlighted code blocks
- **Bash Tool**: Displays command descriptions in summary with bash syntax highlighting  
- **Edit Tool**: Before/After sections showing old and new code with syntax highlighting
- **TodoWrite Tool**: Emoji-enhanced task lists (✅ completed, 🔄 in progress, ⏳ pending)

### Advanced Features
- **Universal Path Relativization**: All absolute project paths converted to relative paths
- **Smart Tool Pairing**: Automatically pairs tool_use with corresponding tool_result messages
- **Embedded Syntax Highlighting**: Self-contained HTML exports with Prism.js supporting Ruby, JavaScript, Python, TypeScript, JSON, Markdown, YAML, Bash and more
- **Robust Message Processing**: Handles edge cases like tool-only messages and system filtering
- **Date Filtering**: Filter conversations by date range or today only (timezone-aware)
- **Multiple Session Combining**: Automatically combines multiple sessions into single chronologically ordered output
- **Thinking Message Support**: Displays thinking content with blockquotes and special emoji (🤖💭)
- **Skip Logging**: Comprehensive JSONL logs of skipped messages during export with reasons
- **Message ID Tracking**: HTML comments with Claude message IDs for cross-referencing
- **Individual File Processing**: Process specific JSONL files instead of scanning directories
- **Secret Detection & Redaction**: Automatic detection and redaction of API keys, tokens, and other secrets using GitLab's proven ruleset

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

# Export from different project directory
./bin/ccexport --in /path/to/project

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

# Use custom template
./bin/ccexport --preview --template mytheme

# Use GitHub-style template
./bin/ccexport --preview --template github

# Process a specific JSONL file instead of scanning directories
./bin/ccexport --jsonl /path/to/conversation.jsonl --out specific-conversation.md

# Combine multiple options
./bin/ccexport --in /path/to/project --from 2024-01-15 --out ./my-exports --timestamps --preview
```

#### Command Line Options

- `--in PATH`: Project path to export conversations from (default: current directory)
- `--from DATE`: Filter messages from this date (YYYY-MM-DD or timestamp format from --timestamps output)
- `--to DATE`: Filter messages to this date (YYYY-MM-DD or timestamp format from --timestamps output)
- `--today`: Filter messages from today only (in your local timezone)
- `--out PATH`: Custom output directory or specific file path (supports relative paths, use .md extension for specific file)
- `--timestamps`: Show precise timestamps with each message for easy reference
- `--preview`: Generate HTML preview and open in browser automatically
- `--no-open`: Generate HTML preview without opening in browser (requires --preview)
- `--template NAME_OR_PATH`: HTML template name (from templates dir) or file path (default: default)
- `--jsonl FILE`: Process a specific JSONL file instead of scanning directories
- `--help`: Show usage information

### Available Templates

The exporter includes several built-in templates:

- **`default`**: Clean, modern styling with rounded corners and a warm color palette
- **`github`**: Mimics GitHub's markdown rendering with GitHub's official color scheme and typography

You can also create custom templates by placing `.html.erb` files in the `lib/templates/` directory or by specifying a full file path.

## Output Format

The exporter creates Markdown files with:

- **Session metadata**: Session ID, timestamps (in local timezone), message counts
- **User messages**: Marked with 👤 User
- **Assistant messages**: Marked with 🤖 Assistant  
- **Thinking messages**: Marked with 🤖💭 Assistant with blockquoted content
- **Tool use**: Marked with 🤖🔧 Assistant with collapsible sections and syntax highlighting
- **Multiple sessions**: Combined into single file with clear session separators
- **Relative paths**: All project paths converted to relative format
- **Message IDs**: HTML comments with Claude message IDs for reference
- **Skip logging**: Separate JSONL files documenting skipped messages with reasons
- **Secret detection logs**: JSONL files documenting detected and redacted secrets with security warnings
- **Clean formatting**: Optimized for GitHub and other Markdown viewers

### Example Output

For complete examples of the exported format, see the sample files in this repository:

- **[VIBE.md](VIBE.md)** - Full conversation export showing all features including tool use, thinking messages, message IDs, and formatting
- **[VIBE.html](VIBE.html)** - HTML preview version with default template styling and embedded Prism.js syntax highlighting

These files demonstrate real conversation exports with:
- Multiple message types (user, assistant, thinking)
- Tool use with collapsible sections and syntax highlighting  
- Message ID HTML comments for cross-referencing
- Path relativization and clean formatting
- All advanced formatting features in action

The VIBE files showcase advanced features like collapsible tool sections, syntax highlighting, thinking message formatting, and proper message threading that would be impractical to show in README snippets.

## Skip Logging

The exporter automatically generates detailed logs of any messages that were skipped during processing. These logs are saved as JSONL files alongside your exported Markdown.

### Skip Log Features

- **Comprehensive tracking**: Every filtered message is logged with full context
- **Structured format**: JSONL format for easy programmatic analysis
- **Detailed reasons**: Specific explanations for why each message was skipped
- **Line references**: Exact line numbers from the original JSONL file
- **Full message data**: Complete JSON data for each skipped message

### Common Skip Reasons

- `leaf summary message`: Summary messages at conversation ends
- `api error or meta message`: System errors and metadata
- `empty or system-generated message`: Empty content or system messages
- `outside date range`: Messages filtered by --from/--to options (not logged)

### Example Skip Log Entry

```json
{"line":42,"reason":"api error or meta message","data":{"type":"meta","error":"rate_limit"}}
```

## Message ID Tracking

Each message in the exported Markdown includes HTML comments with Claude message IDs for easy cross-referencing. You can see this in action throughout the [VIBE.md](VIBE.md) file where each message heading includes a comment like `<!-- msg_01RMr1PPo2ZiRmwHQzgYfovs -->`.

This allows you to:
- Track specific messages across different exports
- Reference messages in documentation or bug reports
- Correlate with Claude's internal logging if needed

## Secret Detection

**⚠️ IMPORTANT SECURITY NOTICE ⚠️**

The exporter automatically scans conversation content for common secrets and sensitive information, then **automatically redacts detected secrets** before export. However, **you are still responsible for reviewing your exports** before sharing them publicly.

### Automatic Detection & Redaction

The tool uses the [`gitlab-secret_detection`](https://rubygems.org/gems/gitlab-secret_detection) gem to detect and redact:

- **API Keys**: AWS access keys, Google API keys, Azure tokens
- **Authentication Tokens**: GitHub personal access tokens, GitLab tokens
- **Service Tokens**: Slack bot tokens, Stripe keys, webhook URLs
- **Private Keys**: SSH keys, TLS certificates, JWT secrets
- **Database Credentials**: Connection strings, passwords
- **And 85+ other secret patterns** from GitLab's proven security ruleset

### Detection & Redaction Process

When secrets are detected, the exporter:

1. **Automatically redacts** detected secrets using GitLab's proven masking algorithm
2. **Continues the export** with redacted content (non-blocking)
3. **Creates a detailed log** file: `*_secrets.jsonl`
4. **Shows a warning** with the count of detected secrets
5. **Logs structured data** including secret type, location, and context

### Example Warning Output

```bash
⚠️  Detected 3 potential secrets in conversation content (see conversation_secrets.jsonl)
   Please review and ensure no sensitive information is shared in exports.
```

### Secret Log Format

The generated `*_secrets.jsonl` file contains structured data for each detection:

```json
{"context":"message_msg_01ABC123_text","type":"AWS","line":1,"description":"AWS access token"}
{"context":"message_msg_01XYZ789_text","type":"Slack token","line":2,"description":"Slack bot user OAuth token"}
```

### Best Practices

1. **Review both the export and secrets log** before sharing
2. **Check for context-specific secrets** the detector might miss
3. **Consider using fake/example data** in conversations you plan to export
4. **Manually review redacted areas** to ensure proper masking
5. **Use the `--jsonl` option** to process specific conversations when unsure

### Redaction Examples

Original content with secrets:
```
Here's my AWS key: AKIAIOSFODNN7EXAMPLE
And my Slack token: xoxb-1234567890-1234567890123-abcdefghijklmnop
```

Automatically redacted output:
```
Here's my AWS key: AKI*****ODN*****MPL*
And my Slack token: xox*****456*****123*****901*****cde*****klm***
```

### Limitations

- Detection is **pattern-based** and may have false positives/negatives
- **Context-specific secrets** (like internal URLs, custom API endpoints) may not be detected
- **Redaction uses conservative masking** - some non-secrets may be masked if they match patterns
- **Human review is always required** before sharing

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
- **Integrated HTML Preview**: Generate and open HTML previews with GitHub styling and embedded Prism.js syntax highlighting
- **Skip Logging & Message Tracking**: JSONL logs of filtered messages and HTML comment message IDs
- **Individual File Processing**: Direct JSONL file processing with `--jsonl` option
- **Secret Detection & Redaction**: Automatic security scanning and redaction using GitLab's secret detection ruleset
- **Comprehensive testing**: 96 RSpec tests covering all functionality including secret detection
- **Ruby-idiomatic**: Clean, maintainable Ruby code structure

## Requirements

- Ruby 2.7+
- Claude Code installed and configured
- RSpec (for testing)
- cmark-gfm (for HTML preview generation): `brew install cmark-gfm`

## Example Files

The `VIBE.md` and `VIBE.html` files in this repository are examples generated from the actual Claude Code conversation that was used to build this tool. They demonstrate the full export functionality and formatting capabilities.

## License

MIT License - feel free to use and modify as needed.