# Claude Code Conversation Exporter (Ruby)

A Ruby tool to export Claude Code conversations to GitHub-flavored Markdown format, or using templates, styled to look similar to Claude Desktop conversations, GitHub or, really any other style, for easy reading.

&lt;noai&gt;
I created this tool because, as I'm exploring using agentic coding tools, I've found myself wanting to share examples with friends and colleagues, so we can learn from each other. I have tried to fully vibe code this project, but I have, on occasion, gone rogue and hand coded tooling to help me and Claude better understand the JSONL structure or fix issues that it seemed to struggle with. I've used other tools, like Claude Desktop with Opus 4.1 and the humble web search. In fact, the very beginning of this project was conducted in Claude Desktop where I asked it to research tooling that already does what I was trying to do.
&lt;/noai&gt;

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
- **Secret Detection & Redaction**: Automatic detection and redaction of API keys, tokens, and other secrets using TruffleHog's industry-standard detection engine

## Installation

### Quick Install (If you already have Ruby)

```bash
gem install ccexport
```

**Note**: If you have Homebrew installed, ccexport will automatically install missing dependencies (TruffleHog and cmark-gfm) when you first run it. If you don't have Homebrew, see the full setup instructions below.

### Full Setup (For non-Ruby developers)

If you don't have Ruby installed or aren't familiar with Ruby development, follow these steps:

#### 1. Install Package Manager (if needed)

**macOS users:** If you don't have Homebrew installed:

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Follow the "Next steps" instructions shown after installation to add Homebrew to your PATH
```

**Windows users with WSL (Windows Subsystem for Linux):**

```bash
# First, ensure you're running Ubuntu/Debian in WSL
# Install Homebrew for Linux
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to your PATH (replace USERNAME with your actual username)
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
source ~/.bashrc

# Install build dependencies
sudo apt-get update
sudo apt-get install build-essential
```

**Ubuntu/Debian users (native Linux):**

**Recommended: Use Homebrew for easier dependency management**

```bash
# Install Homebrew for Linux (same as WSL instructions)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to your PATH
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
source ~/.bashrc

# Install build dependencies
sudo apt-get update
sudo apt-get install build-essential
```

<details>
<summary>Alternative: System package manager (more complex dependency management)</summary>

```bash
# Install basic dependencies
sudo apt-get update
sudo apt-get install curl git build-essential

# Note: You'll need to manually install TruffleHog and cmark-gfm
# TruffleHog: https://github.com/trufflesecurity/trufflehog#installation
# cmark-gfm: You may need to build from source or find alternative packages
```
</details>

#### 2. Install Ruby Version Manager

**If you don't have a Ruby version manager yet, we recommend rbenv:**

```bash
# macOS with Homebrew
brew install rbenv ruby-build

# Ubuntu/Debian
sudo apt install rbenv

# Add rbenv to your shell
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
# or for zsh users:
echo 'eval "$(rbenv init -)"' >> ~/.zshrc

# Restart your terminal or run:
source ~/.bashrc  # or ~/.zshrc
```

**If you already use a different Ruby version manager:**

<details>
<summary>RVM Users</summary>

```bash
# Install latest Ruby 3.4
rvm install 3.4
rvm use 3.4 --default
```
</details>

<details>
<summary>asdf Users</summary>

```bash
# Add Ruby plugin if not already added
asdf plugin add ruby

# Install latest Ruby 3.4
asdf install ruby latest:3.4
asdf global ruby latest:3.4
```
</details>

<details>
<summary>mise Users (formerly rtx)</summary>

```bash
# Install latest Ruby 3.4
mise install ruby@3.4
mise global ruby@3.4
```
</details>

#### 3. Install Ruby 3.4 (rbenv users)

```bash
# Install latest Ruby 3.4
rbenv install 3.4.3
rbenv global 3.4.3

# Verify installation
ruby --version  # Should show Ruby 3.4.3
```

#### 4. Install ccexport

```bash
# Install the gem
gem install ccexport

# Run ccexport - it will automatically install dependencies via Homebrew if needed
ccexport --help
```

**That's it!** When you first run ccexport, it will automatically detect and install any missing dependencies (TruffleHog and cmark-gfm) if you have Homebrew installed.

**Manual dependency installation** (only needed if you don't have Homebrew):
```bash
# If you're using system package managers instead of Homebrew:
# - TruffleHog: https://github.com/trufflesecurity/trufflehog#installation  
# - cmark-gfm: May require building from source on some Linux distributions

# To skip dependency checking entirely:
ccexport --skip-dependency-check
```

### From Source (Development)

1. Clone this repository
2. Install dependencies: `bundle install`
3. Install TruffleHog for secret detection: `brew install trufflehog`

### Prerequisites Summary

- **Ruby**: 3.0.0 or higher (3.4.3 recommended)
- **Homebrew**: Recommended for automatic dependency installation ([installation guide](https://brew.sh))
- **TruffleHog** and **cmark-gfm**: Automatically installed via Homebrew when you first run ccexport

**Manual installation only needed if you don't have Homebrew:**
- **TruffleHog**: For secret detection ([installation guide](https://github.com/trufflesecurity/trufflehog#installation))
- **cmark-gfm**: For HTML preview generation

## Usage

### Simple Usage

Run the exporter in any directory where you've used Claude Code:

```bash
# Basic usage - export all conversations
ccexport
```

### Ruby API Usage

```ruby
require 'ccexport'

ClaudeConversationExporter.export
```

### Command Line Usage

```bash
# Basic usage - export all conversations
ccexport

# Filter by date range
ccexport --from 2024-01-01 --to 2024-01-31

# Filter using timestamp format (copy from --timestamps output)
ccexport --from "August 09, 2025 at 06:03:43 PM"

# Export only today's conversations
ccexport --today

# Export from different project directory
ccexport --in /path/to/project

# Custom output directory
ccexport --out /path/to/output

# Export to specific markdown file with preview
ccexport --out myconversation.md --preview

# Include timestamps
ccexport --timestamps

# Generate HTML preview and open in browser
ccexport --preview

# Generate HTML preview without opening browser
ccexport --preview --no-open

# Use custom template
ccexport --preview --template mytemplate

# Use GitHub template
ccexport --preview --template github

# Process specific JSONL file
ccexport --jsonl /path/to/conversation.jsonl --out specific-conversation.md

# Silent mode (suppress all output)
ccexport --silent

# Complex example: custom project, date range, output, timestamps, and preview
ccexport --in /path/to/project --from 2024-01-15 --out ./my-exports --timestamps --preview
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
- `-s`, `--silent`: Silent mode - suppress all output except errors
- `--help`: Show usage information

### Custom Usage

```ruby
require_relative 'lib/claude_conversation_exporter'

# Export from specific project path to custom output directory
exporter = ClaudeConversationExporter.new('/path/to/project', 'my-conversations')
result = exporter.export

puts "Exported #{result[:sessions_exported]} conversations"
puts "Total messages: #{result[:total_messages]}"
```

### Available Templates

The exporter includes several built-in templates:

- **`default`**: Clean, modern styling with rounded corners and a warm color palette
- **`github`**: Mimics GitHub's markdown rendering with GitHub's official color scheme and typography
- **`solarized`**: Beautiful Solarized color scheme with automatic light/dark mode detection based on user's system preference

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

The tool uses [TruffleHog](https://github.com/trufflesecurity/trufflehog), the industry-standard secret detection engine, to detect and redact:

- **AWS Credentials**: Access keys and secret keys (requires both for detection)
- **GitHub Tokens**: Personal access tokens, fine-grained tokens, OAuth tokens
- **Slack Webhooks**: Incoming webhook URLs and service integrations
- **API Keys**: Google Cloud, Azure, Stripe, and 800+ other services
- **Authentication Tokens**: JWT tokens, OAuth tokens, session tokens
- **Private Keys**: SSH keys, TLS certificates, PGP keys
- **Database Credentials**: Connection strings, passwords
- **And 800+ other secret types** from TruffleHog's actively maintained detection rules

### Detection & Redaction Process

When secrets are detected, the exporter:

1. **Automatically redacts** detected secrets with `[REDACTED]` placeholders
2. **Continues the export** with redacted content (non-blocking)
3. **Creates a detailed log** file: `*_secrets.jsonl`
4. **Shows a warning** with the count of detected secrets
5. **Logs structured data** including detector name, verification status, and context

### Example Warning Output

```bash
⚠️  Detected 3 potential secrets in conversation content (see conversation_secrets.jsonl)
   Please review and ensure no sensitive information is shared in exports.
```

### Secret Log Format

The generated `*_secrets.jsonl` file contains structured data for each detection:

```json
{"context":"message_msg_01ABC123_text","type":"secret","pattern":"AWS","confidence":false}
{"context":"message_msg_01XYZ789_text","type":"secret","pattern":"SlackWebhook","confidence":false}
```

**Field explanations:**
- `context`: Unique identifier for the message location
- `type`: Always "secret" for TruffleHog detections
- `pattern`: TruffleHog detector name (e.g., "AWS", "Github", "SlackWebhook")
- `confidence`: Boolean indicating if the secret was verified against the actual service

### Best Practices

1. **Review both the export and secrets log** before sharing
2. **Check for context-specific secrets** the detector might miss
3. **Consider using fake/example data** in conversations you plan to export
4. **Manually review redacted areas** to ensure proper masking
5. **Use the `--jsonl` option** to process specific conversations when unsure

### Redaction Examples

Original content with secrets:
```
Here's my GitHub token: ghp_1234567890123456789012345678901234567890
AWS credentials: AKIA1234567890123456 secret: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Slack webhook: https://hooks.slack.com/services/T1234567890/B1234567890/abcdefghijklmnopqrstuvwx
```

Automatically redacted output:
```
Here's my GitHub token: [REDACTED]
AWS credentials: [REDACTED] secret: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Slack webhook: [REDACTED]
```

**Note:** TruffleHog focuses on high-confidence secret patterns. Some parts may remain unredacted if they don't match specific detection patterns, which reduces false positives but requires manual review.

### Limitations

- Detection uses **800+ proven patterns** but may miss context-specific secrets
- **TruffleHog is conservative** - it prioritizes avoiding false positives over catching everything
- **Custom/internal secrets** (like internal URLs, custom API endpoints) may not be detected
- **AWS detection requires both** access key and secret key for optimal detection
- **Slack tokens** may not be detected if they don't match exact format patterns
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
- **Secret Detection & Redaction**: Automatic security scanning and redaction using TruffleHog's industry-standard detection engine
- **Comprehensive testing**: 96 RSpec tests covering all functionality including secret detection
- **Ruby-idiomatic**: Clean, maintainable Ruby code structure

## Requirements

- Ruby 2.7+
- Claude Code installed and configured
- TruffleHog (for secret detection): `brew install trufflehog`
- RSpec (for testing)
- cmark-gfm (for HTML preview generation): `brew install cmark-gfm`

## Example Files

The repository includes comprehensive examples generated from the actual Claude Code conversation that was used to build this tool:

### Generated Examples

- **[VIBE.md](VIBE.md)** - Conversation export showing all features including tool use, thinking messages, message IDs, and formatting (67 messages)
- **[VIBE_default.html](VIBE_default.html)** - HTML preview with default template styling and embedded Prism.js syntax highlighting
- **[VIBE_github.html](VIBE_github.html)** - HTML preview with GitHub-style template mimicking GitHub's markdown rendering
- **[VIBE_solarized.html](VIBE_solarized.html)** - HTML preview with Solarized template featuring automatic dark/light mode detection and clickable theme toggle

### Full Scale Example

- **[VIBE_full.md](VIBE_full.md)** - Complete conversation export with all 3,806 messages across 5 sessions (7.3MB)
- **[VIBE_full.html](VIBE_full.html)** - Complete HTML preview with default template (7.9MB)

> **Note:** The full version demonstrates the exporter's capability to handle large, multi-session conversations that span the entire development of this tool. The regular VIBE examples above are filtered to a manageable size for easy browsing and template comparison.

### Features Demonstrated

These examples showcase:
- Multiple message types (user, assistant, thinking)
- Tool use with collapsible sections and syntax highlighting
- Message ID HTML comments for cross-referencing
- Path relativization and clean formatting
- All advanced formatting features in action
- Template comparison across different styling approaches

### Regenerating Examples

Use the included script to regenerate examples for all templates:

```bash
./generate_vibe_samples
```

This automatically creates VIBE sample files for each available template, making it easy to compare styling and features across all templates.

## License

MIT License - feel free to use and modify as needed.
