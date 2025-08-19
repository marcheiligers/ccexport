# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/claude_conversation_exporter_spec.rb

# Run tests for a specific feature
bundle exec rspec spec/secret_detection_spec.rb

# Run tests with documentation output
bundle exec rspec --format documentation
```

### Installation & Dependencies
```bash
# Install Ruby dependencies
bundle install

# Install TruffleHog (required for secret detection)
brew install trufflehog

# Install cmark-gfm (required for HTML preview generation)
brew install cmark-gfm
```

### Running the Tool
```bash
# Basic export (all conversations)
./bin/ccexport

# Export with HTML preview
./bin/ccexport --preview

# Export specific date range
./bin/ccexport --from 2024-01-01 --to 2024-01-31 --preview

# Generate VIBE examples for all templates
./generate_vibe_samples
```

## Architecture Overview

### Core Components

**ClaudeConversationExporter** (`lib/claude_conversation_exporter.rb`)
- Main class handling conversation discovery, parsing, and export
- Uses class methods for simple API: `ClaudeConversationExporter.export`
- Handles both single session and multi-session exports
- Integrates secret detection, path relativization, and HTML generation

**TruffleHogSecretDetector** (`lib/secret_detector.rb`) 
- Wrapper around TruffleHog external command for secret detection
- Uses temporary files and JSON parsing to interface with TruffleHog
- Provides `scan()` and `redact()` methods with Finding objects
- Backward compatible with previous SecretDetector interface

**CLI Interface** (`bin/ccexport`)
- OptionParser-based command line interface
- Supports date filtering, custom paths, templates, and preview generation
- Handles both directory scanning and specific JSONL file processing

### Data Flow

1. **Discovery**: Finds Claude Code session files (`.jsonl`) in `~/.claude/projects/` subdirectories
2. **Parsing**: Reads JSONL files line by line, extracting messages and metadata
3. **Processing**: 
   - Pairs tool_use with tool_result messages across message boundaries
   - Filters messages by date range if specified
   - Applies specialized formatting for different tool types (Write, Bash, Edit, TodoWrite)
4. **Path Relativization**: Converts absolute project paths to relative paths throughout content
5. **Secret Detection**: Scans entire final markdown content with TruffleHog and redacts findings
6. **Output**: Generates markdown and optional HTML preview

### Template System

**Template Location**: `lib/templates/*.html.erb`
- `default.html.erb`: Clean modern styling with warm colors
- `github.html.erb`: GitHub-style rendering  
- `solarized.html.erb`: Solarized color scheme with automatic dark/light mode detection and clickable theme toggle

**Template Features**:
- ERB templating with `<%= content %>` and `<%= title %>` variables
- Embedded Prism.js syntax highlighting from `lib/assets/`
- CSS custom properties for theme consistency
- Responsive design with proper mobile support

### Syntax Highlighting (Prism.js)

**Current Language Support**: Markup/HTML, CSS, C-like, JavaScript, Ruby, Python, Markdown, TypeScript, JSON, YAML, Bash

**Adding New Languages**:
1. Download language component from CDN:
   ```bash
   curl -s "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-LANGUAGE.min.js" \
     -o lib/assets/prism-LANGUAGE.js
   ```

2. Add component filename to `include_prism` method in `lib/claude_conversation_exporter.rb`:
   ```ruby
   language_components = %w[
     prism-python.js
     prism-markdown.js
     prism-typescript.js
     prism-json.js
     prism-yaml.js
     prism-bash.js
     prism-LANGUAGE.js  # <- Add new language here
   ]
   ```

3. Update README.md language list if needed

**Language Component Files**: Kept separate in `lib/assets/prism-*.js` for maintainability. The `include_prism` method dynamically loads and concatenates all components.

### Message Processing Pipeline

**Tool Pairing Logic**: Complex cross-message matching where `tool_use` messages are paired with subsequent `tool_result` messages based on tool ID, even when they appear in separate user/assistant message blocks.

**Content Extraction**: Handles different Claude message content types:
- `text`: Plain text content
- `tool_use`: Formatted as collapsible sections with syntax highlighting
- `thinking`: Displayed as blockquotes with special emoji indicators

**Filtering**: System-generated messages and leaf summaries are filtered out, with comprehensive logging in `*_skipped.jsonl` files.

## Special Considerations

### Secret Detection
- Runs TruffleHog on final markdown content (not individual messages)
- Creates `*_secrets.jsonl` logs with context information
- Uses `[REDACTED]` replacement strategy
- External dependency on `trufflehog` command

### Claude Code Session Discovery
- Automatically discovers sessions in `~/.claude/projects/` subdirectories
- Handles complex project path mappings and multiple session files per project
- Session directory structure: `~/.claude/projects/{escaped-project-path}/`

### VIBE Examples
- `VIBE.md` and `VIBE_*.html`: Limited examples (67 messages) for easy browsing
- `VIBE_full.md` and `VIBE_full.html`: Complete conversation (3,806 messages) demonstrating scalability
- `./generate_vibe_samples` script regenerates all template examples automatically

### Testing Strategy
- 96 RSpec tests covering all major functionality
- Test fixtures in `spec/fixtures/` with real JSONL data samples
- Mocking of external dependencies (TruffleHog, cmark-gfm, system commands)
- Comprehensive secret detection testing with realistic secret formats

## Gem Distribution

### RubyGem Structure
- **Gem Name**: `ccexport`
- **Version**: Managed in `lib/ccexport/version.rb`
- **Executable**: `exe/ccexport` (installed globally as `ccexport` command)
- **Entry Point**: `lib/ccexport.rb` (requires all necessary components)

### Dependency Management
**Automatic Installation**: The `exe/ccexport` executable includes automatic dependency checking and installation:

1. **Dependency Detection**: Checks for `trufflehog` and `cmark-gfm` using `which` command
2. **Auto-Install**: If Homebrew is available, automatically runs `brew install` for missing dependencies
3. **Graceful Fallback**: Provides installation instructions and exits if dependencies can't be auto-installed
4. **Skip Option**: `--skip-dependency-check` flag for advanced users or CI environments
5. **Silent Mode**: Respects `--silent` flag for dependency operations

### Build and Release Process
```bash
# Build gem locally
gem build ccexport.gemspec

# Install locally for testing
gem install ./ccexport-0.1.0.gem

# Test functionality
ccexport --help
```

**Files Excluded from Gem**:
- Test files (`spec/`)
- Development scripts (`debug_compacted.rb`, `generate_vibe_samples`)
- Example outputs (`VIBE*`, `claude-conversations/`)
- Build artifacts (`*.gem`)

### Installation Paths
- **Quick Install**: `gem install ccexport` (dependencies auto-installed with Homebrew)
- **Development**: Clone repo, `bundle install`, manual dependency installation
- **Manual Setup**: Detailed Ruby + Homebrew installation instructions for non-developers