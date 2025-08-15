require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe ClaudeConversationExporter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:claude_home) { File.join(temp_dir, '.claude') }
  let(:projects_dir) { File.join(claude_home, 'projects') }
  let(:project_path) { '/Users/test/my_project' }
  let(:encoded_project_path) { '-Users-test-my-project' }
  let(:session_dir) { File.join(projects_dir, encoded_project_path) }
  let(:output_dir) { File.join(temp_dir, 'output') }

  before do
    FileUtils.mkdir_p(session_dir)
    allow(Dir).to receive(:home).and_return(temp_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'finds Claude home directory' do
      exporter = create_silent_exporter(project_path, output_dir)
      expect(exporter.instance_variable_get(:@claude_home)).to eq(claude_home)
    end

    it 'raises error when Claude home not found' do
      FileUtils.rm_rf(claude_home)
      expect { described_class.new(project_path, output_dir) }.to raise_error(/Claude home directory not found/)
    end

    it 'accepts date filtering options' do
      options = { from: '2024-01-01', to: '2024-01-02' }
      exporter = described_class.new(project_path, output_dir, options.merge(silent: true))
      expect(exporter.instance_variable_get(:@options)).to eq(options.merge(silent: true))
    end

    it 'sets up today filter correctly' do
      options = { today: true }
      allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15, 12, 0, 0, '+00:00'))

      exporter = described_class.new(project_path, output_dir, options.merge(silent: true))
      from_time = exporter.instance_variable_get(:@from_time)
      to_time = exporter.instance_variable_get(:@to_time)

      expect(from_time.strftime('%Y-%m-%d %H:%M:%S')).to eq('2024-01-15 00:00:00')
      expect(to_time.strftime('%Y-%m-%d %H:%M:%S')).to eq('2024-01-15 23:59:59')
    end
  end

  describe '#export' do
    let(:session_file) { File.join(session_dir, 'test-session.jsonl') }
    let(:jsonl_content) do
      [
        {
          'message' => { 'role' => 'user', 'content' => 'Hello, how are you?' },
          'timestamp' => '2024-01-01T10:00:00Z'
        },
        {
          'message' => { 'role' => 'assistant', 'content' => 'I am doing well, thank you!' },
          'timestamp' => '2024-01-01T10:00:30Z'
        }
      ].map(&:to_json).join("\n")
    end

    before do
      File.write(session_file, jsonl_content)
      allow_any_instance_of(described_class).to receive(:system) # Mock notification
    end

    it 'exports conversations to markdown' do
      result = create_silent_exporter(project_path, output_dir).export

      expect(result[:sessions_exported]).to eq(1)
      expect(result[:total_messages]).to eq(2)
      expect(Dir.glob(File.join(output_dir, '*.md')).length).to eq(1)
    end

    it 'combines multiple sessions into single output file' do
      # Create second session file
      second_session_file = File.join(session_dir, 'session2.jsonl')
      second_jsonl_content = [
        {
          'message' => { 'role' => 'user', 'content' => 'Second session message' },
          'timestamp' => '2024-01-02T10:00:00Z'
        }
      ].map(&:to_json).join("\n")

      File.write(second_session_file, second_jsonl_content)

      result = create_silent_exporter(project_path, output_dir).export

      expect(result[:sessions_exported]).to eq(2)
      expect(result[:total_messages]).to eq(3)
      expect(Dir.glob(File.join(output_dir, '*.md')).length).to eq(1)

      # Check combined content
      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      expect(content).to include('# Claude Code Conversation')
      expect(content).to include('**Sessions:** 2')
      expect(content).to include('# Session 2')
      expect(content).to include('Hello, how are you?')
      expect(content).to include('Second session message')
    end

    it 'sorts sessions chronologically by first timestamp' do
      # Create sessions with out-of-order timestamps
      earlier_session_file = File.join(session_dir, 'earlier.jsonl')
      later_session_file = File.join(session_dir, 'later.jsonl')

      # Later session (written first)
      later_content = [
        {
          'message' => { 'role' => 'user', 'content' => 'Later session message' },
          'timestamp' => '2024-01-03T10:00:00Z'
        }
      ].map(&:to_json).join("\n")

      # Earlier session (written second)
      earlier_content = [
        {
          'message' => { 'role' => 'user', 'content' => 'Earlier session message' },
          'timestamp' => '2024-01-01T10:00:00Z'
        }
      ].map(&:to_json).join("\n")

      File.write(later_session_file, later_content)
      File.write(earlier_session_file, earlier_content)

      result = create_silent_exporter(project_path, output_dir).export

      # Check that sessions are in chronological order in the output
      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      # Earlier message should appear before later message
      earlier_pos = content.index('Earlier session message')
      later_pos = content.index('Later session message')

      expect(earlier_pos).to be < later_pos
    end

    it 'creates properly formatted markdown' do
      create_silent_exporter(project_path, output_dir).export

      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      expect(content).to include('# Claude Code Conversation')
      expect(content).to include('## 👤 User')
      expect(content).to include('## 🤖 Assistant')
      expect(content).to include('Hello, how are you?')
      expect(content).to include('I am doing well, thank you!')
    end

    it 'formats session metadata with proper line breaks' do
      create_silent_exporter(project_path, output_dir).export

      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      # Check that session metadata appears on separate lines
      lines = content.split("\n")
      session_line = lines.find { |line| line.include?('**Session:**') }
      started_line = lines.find { |line| line.include?('**Started:**') }
      messages_line = lines.find { |line| line.include?('**Messages:**') }

      expect(session_line).to match(/^\*\*Session:\*\* `test-session`$/)
      expect(started_line).to match(/^\*\*Started:\*\* /)
      expect(messages_line).to match(/^\*\*Messages:\*\* \d+ \(\d+ user, \d+ assistant\)$/)
    end

    it 'converts timestamps to local timezone in headers' do
      # Use UTC timestamp in test data
      utc_content = [
        {
          'message' => { 'role' => 'user', 'content' => 'UTC timestamp test' },
          'timestamp' => '2024-01-15T15:30:00Z'  # 3:30 PM UTC
        }
      ].map(&:to_json).join("\n")

      File.write(session_file, utc_content)

      create_silent_exporter(project_path, output_dir).export

      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      # Should contain local time conversion (will vary by timezone)
      started_line = content.lines.find { |line| line.include?('**Started:**') }
      expect(started_line).to match(/\*\*Started:\*\* January 15, 2024 at \d{1,2}:\d{2} (AM|PM)/)

      # The exact time will depend on system timezone, but format should be correct
      expect(started_line).not_to include('15:30')  # Should not show UTC format
    end

    it 'handles custom output directory from options' do
      custom_output = File.join(temp_dir, 'custom_output')
      options = { out: custom_output }

      # Mock the class method to pass options through
      allow(described_class).to receive(:new).and_call_original

      result = described_class.new(project_path, custom_output, options.merge(silent: true)).export

      expect(result[:sessions_exported]).to eq(1)
      expect(Dir.glob(File.join(custom_output, '*.md')).length).to eq(1)
      expect(Dir.exist?(custom_output)).to be true
    end

    it 'shows timestamps when timestamps option is enabled' do
      options = { timestamps: true }

      result = described_class.new(project_path, output_dir, options.merge(silent: true)).export

      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      # Should include timestamps in message headers
      expect(content).to match(/## 👤 User - \w+ \d{1,2}, \d{4} at \d{1,2}:\d{2}:\d{2} (AM|PM)/)
      expect(content).to match(/## 🤖 Assistant - \w+ \d{1,2}, \d{4} at \d{1,2}:\d{2}:\d{2} (AM|PM)/)
    end

    it 'does not show timestamps by default' do
      result = create_silent_exporter(project_path, output_dir).export

      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)

      # Should not include timestamps in message headers
      expect(content).to match(/^## 👤 User$/)
      expect(content).to match(/^## 🤖 Assistant$/)
      expect(content).not_to match(/## 👤 User - \w+ \d{1,2}, \d{4}/)
    end

    it 'handles empty session files gracefully' do
      File.write(session_file, '')

      result = create_silent_exporter(project_path, output_dir).export

      expect(result[:sessions_exported]).to eq(0)
      expect(result[:total_messages]).to eq(0)
    end

    it 'skips system-generated messages' do
      system_content = [
        {
          'message' => { 'role' => 'user', 'content' => 'Valid message' },
          'timestamp' => '2024-01-01T10:00:00Z'
        },
        {
          'message' => { 'role' => 'system', 'content' => '<system-reminder>Skip this</system-reminder>' },
          'timestamp' => '2024-01-01T10:00:15Z'
        },
        {
          'message' => { 'role' => 'assistant', 'content' => 'Another valid message' },
          'timestamp' => '2024-01-01T10:00:30Z'
        }
      ].map(&:to_json).join("\n")

      File.write(session_file, system_content)

      result = create_silent_exporter(project_path, output_dir).export

      expect(result[:total_messages]).to eq(2) # Only user and assistant messages
    end
  end

  describe '#encode_path' do
    it 'encodes paths correctly' do
      exporter = create_silent_exporter(project_path, output_dir)
      encoded = exporter.send(:encode_path, '/Users/test/my_project')
      expect(encoded).to eq('-Users-test-my-project')
    end

    it 'handles underscores' do
      exporter = create_silent_exporter(project_path, output_dir)
      encoded = exporter.send(:encode_path, '/Users/test/my_project_name')
      expect(encoded).to eq('-Users-test-my-project-name')
    end
  end

  describe '#generate_title' do
    it 'generates title from first user message' do
      exporter = create_silent_exporter(project_path, output_dir)
      messages = [
        { role: 'user', content: 'Help me build a todo app' },
        { role: 'assistant', content: 'Sure!' }
      ]

      title = exporter.send(:generate_title, messages)
      expect(title).to eq('help-me-build-a-todo')
    end

    it 'sanitizes titles properly' do
      exporter = create_silent_exporter(project_path, output_dir)
      messages = [
        { role: 'user', content: 'Fix bug in /api/users endpoint!' }
      ]

      title = exporter.send(:generate_title, messages)
      expect(title).to eq('fix-bug-in-api-users')
    end

    it 'returns untitled for empty messages' do
      exporter = create_silent_exporter(project_path, output_dir)
      title = exporter.send(:generate_title, [])
      expect(title).to eq('untitled')
    end
  end

  describe '#generate_combined_filename' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'generates single session filename when only one session' do
      sessions = [
        { session_id: 'test-123', messages: [{ role: 'user', content: 'Test message' }] }
      ]

      filename = exporter.send(:generate_combined_filename, sessions)
      expect(filename).to match(/\d{8}-\d{6}-test-message-test-123\.md/)
    end

    it 'generates combined filename for multiple sessions' do
      sessions = [
        { session_id: 'session1', messages: [{ role: 'user', content: 'First message' }] },
        { session_id: 'session2', messages: [{ role: 'user', content: 'Second message' }] }
      ]

      filename = exporter.send(:generate_combined_filename, sessions)
      expect(filename).to match(/\d{8}-\d{6}-first-message-combined-2-sessions\.md/)
    end
  end

  describe '#system_generated?' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'identifies system-generated content' do
      expect(exporter.send(:system_generated?, '<system-reminder>Test</system-reminder>')).to be true
      expect(exporter.send(:system_generated?, '<command-name>test</command-name>')).to be true
      expect(exporter.send(:system_generated?, 'Regular user message')).to be false
    end
  end

  describe '#extract_text_content' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'extracts text from content array and formats tool use' do
      content_array = [
        { 'type' => 'text', 'text' => 'Hello there!' },
        { 'type' => 'tool_use', 'name' => 'some_tool', 'input' => { 'param' => 'value' } },
        { 'type' => 'tool_result', 'content' => 'Tool executed successfully' },
        { 'type' => 'text', 'text' => 'How can I help?' }
      ]

      result = exporter.send(:extract_text_content, content_array)
      expect(result[:content]).to include('Hello there!')
      expect(result[:content]).to include('How can I help?')
      expect(result[:content]).to include('## 🤖🔧 Assistant')
      expect(result[:content]).to include('<details>')
      expect(result[:content]).to include('<summary>some_tool</summary>')
      # Tool result is now handled at message pairing level, not content array level
      expect(result[:content]).to include('Tool executed successfully') # Still present as JSON
      expect(result[:has_thinking]).to be false
    end

    it 'handles tool_use without tool_result' do
      content_array = [
        { 'type' => 'tool_use', 'name' => 'some_tool', 'input' => { 'param' => 'value' } }
      ]

      result = exporter.send(:extract_text_content, content_array)
      expect(result[:content]).to include('## 🤖🔧 Assistant')
      expect(result[:content]).to include('<summary>some_tool</summary>')
      expect(result[:content]).not_to include('<summary>Tool Result</summary>')
      expect(result[:has_thinking]).to be false
    end

    it 'preserves non-text, non-tool content as JSON' do
      content_array = [
        { 'type' => 'image', 'data' => 'base64...' }
      ]

      result = exporter.send(:extract_text_content, content_array)
      expect(result[:content]).to include('image')
      expect(result[:content]).to include('base64...')
      expect(result[:has_thinking]).to be false
    end
  end

  describe '#format_tool_use' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'formats tool use with collapsed sections' do
      tool_use = {
        'name' => 'Read',
        'input' => { 'file_path' => '/path/to/file.txt' }
      }
      tool_result = {
        'content' => 'File contents here'
      }

      result = exporter.send(:format_tool_use, tool_use, tool_result)

      expect(result).to include('## 🤖🔧 Assistant')
      expect(result).to include('<details>')
      expect(result).to include('<summary>Read</summary>')
      expect(result).to include('```json')
      expect(result).to include('file_path')
      expect(result).to include('<summary>Tool Result</summary>')
      expect(result).to include('File contents here')
      expect(result).to include('</details>')
    end

    it 'handles tool use without result' do
      tool_use = {
        'name' => 'Write',
        'input' => { 'file_path' => '/path/to/file.txt', 'content' => 'New content' }
      }

      result = exporter.send(:format_tool_use, tool_use)

      expect(result).to include('## 🤖🔧 Assistant')
      expect(result).to include('<summary>Write path/to/file.txt</summary>')
      expect(result).not_to include('<summary>Tool Result</summary>')
    end

    it 'formats TodoWrite tool with emoji status list' do
      tool_use = {
        'name' => 'TodoWrite',
        'input' => {
          'todos' => [
            { 'id' => '1', 'content' => 'First task', 'status' => 'completed' },
            { 'id' => '2', 'content' => 'Second task', 'status' => 'in_progress' },
            { 'id' => '3', 'content' => 'Third task', 'status' => 'pending' }
          ]
        }
      }

      result = exporter.send(:format_tool_use, tool_use)

      expect(result).to include('## 🤖🔧 Assistant')
      expect(result).to include('<summary>TodoWrite</summary>')
      expect(result).to include('✅ First task')
      expect(result).to include('🔄 Second task')
      expect(result).to include('⏳ Third task')
      expect(result).not_to include('```json')
    end
  end

  describe '#format_todo_list' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'formats todos with appropriate status emojis' do
      todos = [
        { 'content' => 'Completed task', 'status' => 'completed' },
        { 'content' => 'In progress task', 'status' => 'in_progress' },
        { 'content' => 'Pending task', 'status' => 'pending' },
        { 'content' => 'Unknown status task', 'status' => 'unknown' }
      ]

      result = exporter.send(:format_todo_list, todos)

      expect(result).to include('✅ Completed task')
      expect(result).to include('🔄 In progress task')
      expect(result).to include('⏳ Pending task')
      expect(result).to include('❓ Unknown status task')
    end

    it 'adds trailing spaces for proper markdown line breaks' do
      todos = [
        { 'content' => 'First task', 'status' => 'completed' },
        { 'content' => 'Second task', 'status' => 'pending' }
      ]

      result = exporter.send(:format_todo_list, todos)

      expect(result).to eq("✅ First task  \n⏳ Second task  ")
    end
  end

  describe '#test_process_message with text extraction' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'extracts text content from assistant array messages and formats tool use' do
      data = {
        'message' => {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'text', 'text' => 'Here is my response.' },
            { 'type' => 'tool_use', 'name' => 'some_tool', 'input' => { 'param' => 'value' } }
          ]
        },
        'timestamp' => '2024-01-01T10:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result[:content]).to include('Here is my response.')
      expect(result[:content]).to include('## 🤖🔧 Assistant')
      expect(result[:content]).to include('<summary>some_tool</summary>')
      expect(result[:role]).to eq('assistant')
    end

    it 'preserves string content for user messages' do
      data = {
        'message' => {
          'role' => 'user',
          'content' => 'This is my question'
        },
        'timestamp' => '2024-01-01T10:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result[:content]).to eq('This is my question')
      expect(result[:role]).to eq('user')
    end
  end

  describe '.export' do
    let(:session_file) { File.join(session_dir, 'test-session.jsonl') }
    let(:jsonl_content) do
      {
        'message' => { 'role' => 'user', 'content' => 'Test message' },
        'timestamp' => '2024-01-01T10:00:00Z'
      }.to_json
    end
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    before do
      File.write(session_file, jsonl_content)
      allow_any_instance_of(described_class).to receive(:system)
    end

    it 'provides class method for easy export' do
      allow(Dir).to receive(:pwd).and_return(project_path)
      result = exporter.export

      expect(result[:sessions_exported]).to be >= 0
      expect(result).to have_key(:total_messages)
    end
  end

  describe '#format_tool_use - enhanced formatting' do
    let(:exporter) { create_silent_exporter('/test/project') }

    describe 'Write tool with relative path and syntax highlighting' do
      it 'formats Write tool with relative path in summary' do
        tool_use = {
          'name' => 'Write',
          'input' => {
            'file_path' => '/test/project/lib/example.rb',
            'content' => 'puts "hello"'
          }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('<summary>Write lib/example.rb</summary>')
        expect(result).to include('```ruby')
        expect(result).to include('puts "hello"')
      end

      it 'detects various file extensions for syntax highlighting' do
        test_cases = [
          { ext: '.js', lang: 'javascript' },
          { ext: '.py', lang: 'python' },
          { ext: '.ts', lang: 'typescript' },
          { ext: '.json', lang: 'json' },
          { ext: '.md', lang: 'markdown' },
          { ext: '.yml', lang: 'yaml' },
          { ext: '.sh', lang: 'bash' }
        ]

        test_cases.each do |test_case|
          tool_use = {
            'name' => 'Write',
            'input' => {
              'file_path' => "/test/project/file#{test_case[:ext]}",
              'content' => 'content'
            }
          }

          result = exporter.send(:format_tool_use, tool_use)
          expect(result).to include("```#{test_case[:lang]}")
        end
      end
    end

    describe 'Bash tool with description and relative paths' do
      it 'formats Bash tool with description in summary' do
        tool_use = {
          'name' => 'Bash',
          'input' => {
            'command' => './bin/test',
            'description' => 'Run test script'
          }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('<summary>Bash: Run test script</summary>')
        expect(result).to include('```bash')
        expect(result).to include('./bin/test')
      end

      it 'uses default description when none provided' do
        tool_use = {
          'name' => 'Bash',
          'input' => { 'command' => 'ls' }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('<summary>Bash: Run bash command</summary>')
      end

      it 'makes paths relative in command' do
        tool_use = {
          'name' => 'Bash',
          'input' => {
            'command' => '/test/project/bin/script && /test/project/lib/test.rb',
            'description' => 'Test with paths'
          }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('./bin/script && ./lib/test.rb')
      end
    end

    describe 'Edit tool with Before/After sections' do
      it 'formats Edit tool with relative path and Before/After sections' do
        tool_use = {
          'name' => 'Edit',
          'input' => {
            'file_path' => '/test/project/src/code.rb',
            'old_string' => 'def old_method\n  puts "old"\nend',
            'new_string' => 'def new_method\n  puts "new"\nend'
          }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('<summary>Edit src/code.rb</summary>')
        expect(result).to include('**Before:**')
        expect(result).to include('**After:**')
        expect(result).to include('```ruby')
        expect(result).to include('def old_method')
        expect(result).to include('def new_method')
      end

      it 'falls back to JSON when old_string/new_string missing' do
        tool_use = {
          'name' => 'Edit',
          'input' => {
            'file_path' => '/test/project/file.txt',
            'some_param' => 'value'
          }
        }

        result = exporter.send(:format_tool_use, tool_use)

        expect(result).to include('```json')
        expect(result).to include('"some_param"')
      end
    end
  end

  describe '#make_paths_relative' do
    let(:exporter) { create_silent_exporter('/test/project') }

    it 'replaces absolute project paths with relative paths' do
      content = 'File at /test/project/lib/file.rb and /test/project/spec/test.rb'

      result = exporter.send(:make_paths_relative, content)

      expect(result).to eq('File at lib/file.rb and spec/test.rb')
    end

    it 'replaces project root path with current directory' do
      content = 'In directory /test/project run command'

      result = exporter.send(:make_paths_relative, content)

      expect(result).to eq('In directory . run command')
    end

    it 'leaves non-project paths unchanged' do
      content = 'System path /usr/bin/ruby and home ~/.bashrc'

      result = exporter.send(:make_paths_relative, content)

      expect(result).to eq('System path /usr/bin/ruby and home ~/.bashrc')
    end
  end

  describe 'system_generated? enhancement' do
    let(:exporter) { create_silent_exporter }

    it 'does not filter out tool use content' do
      tool_content = '## 🤖🔧 Assistant\n<details>\n<summary>Write</summary>'

      result = exporter.send(:system_generated?, tool_content)

      expect(result).to be false
    end

    it 'still filters system patterns in non-tool content' do
      system_content = 'Some text with Caveat: The messages below were generated'

      result = exporter.send(:system_generated?, system_content)

      expect(result).to be true
    end
  end

  describe 'tool_use_ids extraction and filtering' do
    let(:exporter) { create_silent_exporter }

    it 'preserves messages with tool_use even when content is empty after processing' do
      data = {
        'message' => {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'tool_use', 'id' => 'tool123', 'name' => 'Write', 'input' => {} }
          ]
        },
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)

      expect(result).not_to be_nil
      expect(result[:tool_use_ids]).to eq(['tool123'])
      expect(result[:role]).to eq('assistant')
    end

    it 'extracts tool_use_ids from assistant messages' do
      data = {
        'message' => {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'text', 'text' => 'I will write a file' },
            { 'type' => 'tool_use', 'id' => 'tool123', 'name' => 'Write' },
            { 'type' => 'tool_use', 'id' => 'tool456', 'name' => 'Edit' }
          ]
        },
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)

      expect(result[:tool_use_ids]).to eq(['tool123', 'tool456'])
    end
  end

  describe 'linear processing approach' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    it 'skips ignorable message types' do
      data = {
        'isApiErrorMessage' => false,
        'message' => { 'role' => 'assistant', 'content' => 'Some content' }
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result).to be_nil
    end

    it 'processes isCompactSummary messages' do
      data = {
        'isCompactSummary' => true,
        'message' => {
          'role' => 'user',
          'content' => [{'type' => 'text', 'text' => 'This session is being continued...'}]
        },
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result).not_to be_nil
      expect(result[:role]).to eq('user')
      expect(result[:content]).to include('<details>')
      expect(result[:content]).to include('Compacted')
    end

    it 'identifies tool_use messages correctly' do
      data = {
        'requestId' => 'req_123',
        'message' => {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'tool_use', 'id' => 'tool123', 'name' => 'Write' }
          ]
        }
      }

      expect(exporter.send(:tool_use_message?, data)).to be true
    end

    it 'identifies regular messages correctly' do
      data = {
        'message' => { 'role' => 'user', 'content' => 'Regular message' },
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      expect(exporter.send(:regular_message?, data)).to be true
    end

    it 'processes thinking messages correctly' do
      data = {
        'type' => 'thinking',
        'thinking' => 'I need to analyze this problem carefully.',
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result).not_to be_nil
      expect(result[:role]).to eq('assistant_thinking')
      expect(result[:content]).to eq('> I need to analyze this problem carefully.')
    end

    it 'handles multiline thinking content with blockquotes' do
      data = {
        'type' => 'thinking',
        'thinking' => "First line of thinking.\nSecond line of analysis.\nThird line conclusion.",
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result).not_to be_nil
      expect(result[:role]).to eq('assistant_thinking')
      expect(result[:content]).to eq("> First line of thinking.\n> Second line of analysis.\n> Third line conclusion.")
    end

    it 'processes messages with mixed text and thinking content' do
      data = {
        'message' => {
          'role' => 'assistant',
          'content' => [
            { 'type' => 'text', 'text' => 'Let me help you with that.' },
            { 'type' => 'thinking', 'thinking' => 'User needs clarification on the requirements.' },
            { 'type' => 'text', 'text' => 'What specific aspect would you like to focus on?' }
          ]
        },
        'timestamp' => '2025-01-01T00:00:00Z'
      }

      result = exporter.send(:test_process_message, data, 0)
      expect(result).not_to be_nil
      expect(result[:role]).to eq('assistant_thinking')
      expect(result[:content]).to include('Let me help you with that.')
      expect(result[:content]).to include('> User needs clarification on the requirements.')
      expect(result[:content]).to include('What specific aspect would you like to focus on?')
    end
  end

  describe 'date filtering' do
    let(:exporter) { create_silent_exporter(project_path, output_dir) }

    describe '#message_in_date_range?' do
      it 'returns true when no date filters are set' do
        expect(exporter.send(:message_in_date_range?, '2024-01-01T10:00:00Z')).to be true
      end

      it 'filters messages by from date' do
        options = { from: '2024-01-15' }
        filtered_exporter = described_class.new(project_path, output_dir, options.merge(silent: true))

        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-10T10:00:00Z')).to be false
        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-16T10:00:00Z')).to be true
      end

      it 'filters messages by to date' do
        options = { to: '2024-01-15' }
        filtered_exporter = described_class.new(project_path, output_dir, options.merge(silent: true))

        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-14T10:00:00Z')).to be true
        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-16T10:00:00Z')).to be false
      end

      it 'filters messages by date range' do
        options = { from: '2024-01-10', to: '2024-01-15' }
        filtered_exporter = described_class.new(project_path, output_dir, options.merge(silent: true))

        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-05T10:00:00Z')).to be false
        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-12T10:00:00Z')).to be true
        expect(filtered_exporter.send(:message_in_date_range?, '2024-01-20T10:00:00Z')).to be false
      end

      it 'handles invalid timestamps gracefully' do
        expect(exporter.send(:message_in_date_range?, 'invalid-timestamp')).to be true
      end
    end

    describe '#parse_date_input' do
      let(:exporter) { create_silent_exporter(project_path, output_dir) }

      it 'parses YYYY-MM-DD format for start of day' do
        result = exporter.send(:parse_date_input, '2024-01-15', 'from', start_of_day: true)
        expect(result.strftime('%Y-%m-%d %H:%M:%S')).to eq('2024-01-15 00:00:00')
      end

      it 'parses YYYY-MM-DD format for end of day' do
        result = exporter.send(:parse_date_input, '2024-01-15', 'to', start_of_day: false)
        expect(result.strftime('%Y-%m-%d %H:%M:%S')).to eq('2024-01-15 23:59:59')
      end

      it 'parses timestamp format from --timestamps output' do
        result = exporter.send(:parse_date_input, 'August 09, 2025 at 06:03:43 PM', 'from', start_of_day: true)
        expect(result.strftime('%B %d, %Y at %I:%M:%S %p')).to eq('August 09, 2025 at 06:03:43 PM')
      end

      it 'raises error for invalid date format' do
        expect {
          exporter.send(:parse_date_input, 'invalid-date', 'from', start_of_day: true)
        }.to raise_error(/Invalid from date format/)
      end
    end

    describe 'date filtering integration' do
      let(:session_file) { File.join(session_dir, 'filtered-session.jsonl') }

      it 'filters messages during export with date range' do
        filtered_content = [
          {
            'message' => { 'role' => 'user', 'content' => 'Message from Jan 5' },
            'timestamp' => '2024-01-05T10:00:00Z'
          },
          {
            'message' => { 'role' => 'user', 'content' => 'Message from Jan 15' },
            'timestamp' => '2024-01-15T10:00:00Z'
          },
          {
            'message' => { 'role' => 'user', 'content' => 'Message from Jan 25' },
            'timestamp' => '2024-01-25T10:00:00Z'
          }
        ].map(&:to_json).join("\n")

        File.write(session_file, filtered_content)

        options = { from: '2024-01-10', to: '2024-01-20' }
        result = described_class.new(project_path, output_dir, options.merge(silent: true)).export

        expect(result[:total_messages]).to eq(1) # Only Jan 15 message

        markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
        content = File.read(markdown_file)

        expect(content).to include('Message from Jan 15')
        expect(content).not_to include('Message from Jan 5')
        expect(content).not_to include('Message from Jan 25')
      end
    end
  end

  describe '.generate_preview' do
    let(:output_dir) { File.join(temp_dir, 'output') }
    let(:markdown_file) { File.join(output_dir, 'test.md') }
    let(:css_file) { File.join(File.dirname(__FILE__), '..', 'docs', 'github_markdown_cheatsheet.html') }

    before do
      FileUtils.mkdir_p(output_dir)
      File.write(markdown_file, "# Test Markdown\nSome content")
    end

    it 'generates HTML preview when cmark-gfm is available' do
      # Mock system commands
      allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(true)
      allow(described_class).to receive(:`).and_return('<p>Test HTML</p>')
      allow($?).to receive(:exitstatus).and_return(0)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/preview_template\.html\.erb$/).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(/preview_template\.html\.erb$/).and_return('<!DOCTYPE html><html><head><title><%= title %></title></head><body><%= content %></body></html>')
      allow(described_class).to receive(:system).with('open', anything)

      # Mock output to capture messages without printing
      expect(described_class).to receive(:puts).with(/Creating preview for:/).once
      expect(described_class).to receive(:puts).with(/HTML preview:/).once
      expect(described_class).to receive(:puts).with(/Opening in browser/).once

      result = described_class.generate_preview(output_dir, true, [])

      expect(result).to be_a(String)
      expect(result).to end_with('.html')
    end

    it 'returns false when no markdown files exist' do
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)

      # Mock output to suppress puts statements
      expect(described_class).to receive(:puts).with(/No markdown files found/).once

      result = described_class.generate_preview(output_dir, true, [])

      expect(result).to be false
    end

    it 'returns false when cmark-gfm is not available' do
      allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(false)

      # Mock output to suppress puts statements
      expect(described_class).to receive(:puts).with(/Creating preview for:/).once
      expect(described_class).to receive(:puts).with(/Error: cmark-gfm not found/).once
      expect(described_class).to receive(:puts).with(/brew install cmark-gfm/).once

      result = described_class.generate_preview(output_dir, true, [])

      expect(result).to be false
    end

    it 'returns false when ERB template is missing' do
      allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(true)
      allow(described_class).to receive(:`).and_return('<p>Test HTML</p>')
      allow($?).to receive(:exitstatus).and_return(0)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/default\.html\.erb$/).and_return(false)

      # Mock output to suppress puts statements
      expect(described_class).to receive(:puts).with(/Creating preview for:/).once
      expect(described_class).to receive(:puts).with(/Error: ERB template not found/).once

      result = described_class.generate_preview(output_dir, true, [])

      expect(result).to be false
    end

    it 'does not open browser when open_browser is false' do
      # Mock system commands
      allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(true)
      allow(described_class).to receive(:`).and_return('<p>Test HTML</p>')
      allow($?).to receive(:exitstatus).and_return(0)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/preview_template\.html\.erb$/).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(/preview_template\.html\.erb$/).and_return('<!DOCTYPE html><html><head><title><%= title %></title></head><body><%= content %></body></html>')

      # Ensure open command is not called
      expect(described_class).not_to receive(:system).with('open', anything)

      # Mock output to suppress puts statements
      expect(described_class).to receive(:puts).with(/Creating preview for:/).once
      expect(described_class).to receive(:puts).with(/HTML preview:/).once
      expect(described_class).not_to receive(:puts).with(/Opening in browser/)

      result = described_class.generate_preview(output_dir, false, [])

      expect(result).to be_a(String)
      expect(result).to end_with('.html')
    end

    it 'uses leaf summary as title when available' do
      # Mock system commands
      allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(true)
      allow(described_class).to receive(:`).and_return('<p>Test HTML</p>')
      allow($?).to receive(:exitstatus).and_return(0)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/preview_template\.html\.erb$/).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(/preview_template\.html\.erb$/).and_return('<!DOCTYPE html><html><head><title><%= title %></title></head><body><%= content %></body></html>')
      allow(described_class).to receive(:system).with('open', anything)

      # Mock output to suppress puts statements
      expect(described_class).to receive(:puts).with(/Creating preview for:/).once
      expect(described_class).to receive(:puts).with(/HTML preview:/).once
      expect(described_class).to receive(:puts).with(/Opening in browser/).once

      leaf_summaries = [{
        uuid: 'test-uuid',
        summary: 'Ruby Claude Code Exporter Test',
        timestamp: '2025-01-01T00:00:00Z'
      }]

      result = described_class.generate_preview(output_dir, true, leaf_summaries)

      expect(result).to be_a(String)
      expect(result).to end_with('.html')

      # Check that the HTML file contains the leaf summary title
      html_content = File.read(result)
      expect(html_content).to include('<title>Ruby Claude Code Exporter Test</title>')
    end

    describe 'template parameter functionality' do
      before do
        # Mock cmark-gfm system calls
        allow(described_class).to receive(:system).with('which cmark-gfm > /dev/null 2>&1').and_return(true)
        allow(described_class).to receive(:`).and_return('<p>Test HTML content</p>')
        allow($?).to receive(:exitstatus).and_return(0)
        allow(described_class).to receive(:system).with('open', anything)
      end

      it 'uses default template when no template specified' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(/default\.html\.erb$/).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(/default\.html\.erb$/).and_return('<!DOCTYPE html><html><head><title><%= title %></title></head><body><%= content %></body></html>')

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        result = described_class.generate_preview(output_dir, true, [])

        expect(result).to be_a(String)
        expect(result).to end_with('.html')
      end

      it 'uses default template when "default" template name specified' do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(/default\.html\.erb$/).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(/default\.html\.erb$/).and_return('<!DOCTYPE html><html><head><title><%= title %></title></head><body><%= content %></body></html>')

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        result = described_class.generate_preview(output_dir, true, [], 'default')

        expect(result).to be_a(String)
        expect(result).to end_with('.html')
      end

      it 'looks in templates directory for template name' do
        # Create custom template in templates directory
        templates_dir = File.join(File.dirname(__FILE__), '..', 'lib', 'templates')
        FileUtils.mkdir_p(templates_dir)
        custom_template_path = File.join(templates_dir, 'custom.html.erb')

        File.write(custom_template_path, <<~ERB)
          <!DOCTYPE html>
          <html>
          <head><title><%= title %></title></head>
          <body><%= content %></body>
          </html>
        ERB

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        result = described_class.generate_preview(output_dir, true, [], 'custom')

        expect(result).to be_a(String)
        expect(result).to end_with('.html')

        # Cleanup
        File.delete(custom_template_path) if File.exist?(custom_template_path)
      end

      it 'uses full file path when path contains slash' do
        custom_template_path = File.join(temp_dir, 'custom_template.html.erb')
        File.write(custom_template_path, <<~ERB)
          <!DOCTYPE html>
          <html>
          <head><title><%= title %></title></head>
          <body><%= content %></body>
          </html>
        ERB

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        result = described_class.generate_preview(output_dir, true, [], custom_template_path)

        expect(result).to be_a(String)
        expect(result).to end_with('.html')
      end

      it 'uses full file path when path ends with .erb' do
        custom_template_path = File.join(temp_dir, 'my_template.html.erb')
        File.write(custom_template_path, <<~ERB)
          <!DOCTYPE html>
          <html>
          <head><title><%= title %></title></head>
          <body><%= content %></body>
          </html>
        ERB

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        result = described_class.generate_preview(output_dir, true, [], custom_template_path)

        expect(result).to be_a(String)
        expect(result).to end_with('.html')
      end

      it 'returns false when template name does not exist in templates directory' do
        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/Error: ERB template not found/).once

        result = described_class.generate_preview(output_dir, true, [], 'nonexistent')

        expect(result).to be false
      end

      it 'returns false when template file path does not exist' do
        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/Error: ERB template not found/).once

        result = described_class.generate_preview(output_dir, true, [], '/path/to/nonexistent.html.erb')

        expect(result).to be false
      end

      it 'correctly processes ERB variables in custom template' do
        custom_template_path = File.join(temp_dir, 'test_template.html.erb')
        File.write(custom_template_path, <<~ERB)
          <!DOCTYPE html>
          <html>
          <head><title>TITLE: <%= title %></title></head>
          <body>CONTENT: <%= content %></body>
          </html>
        ERB

        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/HTML preview:/).once
        expect(described_class).to receive(:puts).with(/Opening in browser/).once

        leaf_summaries = [{
          uuid: 'test-uuid',
          summary: 'Custom Test Title',
          timestamp: '2024-01-01T12:00:00Z'
        }]

        result = described_class.generate_preview(output_dir, true, leaf_summaries, custom_template_path)

        expect(result).to be_a(String)
        expect(result).to end_with('.html')

        # Check that ERB variables were processed correctly
        html_content = File.read(result)
        expect(html_content).to include('TITLE: Custom Test Title')
        expect(html_content).to include('CONTENT: <p>Test HTML content</p>')
      end

      it 'detects template name vs path correctly based on slash' do
        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).twice
        expect(described_class).to receive(:puts).with(/Error: ERB template not found/).twice

        # Test that it tries templates directory for name without slash
        result = described_class.generate_preview(output_dir, true, [], 'custom')
        expect(result).to be false # Should fail because template doesn't exist

        # Test that it uses exact path when slash is present
        result = described_class.generate_preview(output_dir, true, [], './custom')
        expect(result).to be false # Should fail because file doesn't exist
      end

      it 'detects template name vs path correctly based on .erb extension' do
        # Mock output to suppress puts statements
        expect(described_class).to receive(:puts).with(/Creating preview for:/).once
        expect(described_class).to receive(:puts).with(/Error: ERB template not found/).once

        # Test that it uses exact path when .erb extension is present
        result = described_class.generate_preview(output_dir, true, [], 'custom.html.erb')
        expect(result).to be false # Should fail because file doesn't exist at current location
      end
    end

  end
end
