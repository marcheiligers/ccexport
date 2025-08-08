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
      exporter = described_class.new(project_path, output_dir)
      expect(exporter.instance_variable_get(:@claude_home)).to eq(claude_home)
    end

    it 'raises error when Claude home not found' do
      FileUtils.rm_rf(claude_home)
      expect { described_class.new(project_path, output_dir) }.to raise_error(/Claude home directory not found/)
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
      result = described_class.new(project_path, output_dir).export
      
      expect(result[:sessions_exported]).to eq(1)
      expect(result[:total_messages]).to eq(2)
      expect(Dir.glob(File.join(output_dir, '*.md')).length).to eq(1)
    end

    it 'creates properly formatted markdown' do
      described_class.new(project_path, output_dir).export
      
      markdown_file = Dir.glob(File.join(output_dir, '*.md')).first
      content = File.read(markdown_file)
      
      expect(content).to include('# Claude Code Conversation')
      expect(content).to include('## 👤 User')
      expect(content).to include('## 🤖 Assistant')
      expect(content).to include('Hello, how are you?')
      expect(content).to include('I am doing well, thank you!')
    end

    it 'handles empty session files gracefully' do
      File.write(session_file, '')
      
      result = described_class.new(project_path, output_dir).export
      
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
      
      result = described_class.new(project_path, output_dir).export
      
      expect(result[:total_messages]).to eq(2) # Only user and assistant messages
    end
  end

  describe '#encode_path' do
    it 'encodes paths correctly' do
      exporter = described_class.new(project_path, output_dir)
      encoded = exporter.send(:encode_path, '/Users/test/my_project')
      expect(encoded).to eq('-Users-test-my-project')
    end

    it 'handles underscores' do
      exporter = described_class.new(project_path, output_dir)
      encoded = exporter.send(:encode_path, '/Users/test/my_project_name')
      expect(encoded).to eq('-Users-test-my-project-name')
    end
  end

  describe '#generate_title' do
    it 'generates title from first user message' do
      exporter = described_class.new(project_path, output_dir)
      messages = [
        { role: 'user', content: 'Help me build a todo app' },
        { role: 'assistant', content: 'Sure!' }
      ]
      
      title = exporter.send(:generate_title, messages)
      expect(title).to eq('help-me-build-a-todo')
    end

    it 'sanitizes titles properly' do
      exporter = described_class.new(project_path, output_dir)
      messages = [
        { role: 'user', content: 'Fix bug in /api/users endpoint!' }
      ]
      
      title = exporter.send(:generate_title, messages)
      expect(title).to eq('fix-bug-in-api-users')
    end

    it 'returns untitled for empty messages' do
      exporter = described_class.new(project_path, output_dir)
      title = exporter.send(:generate_title, [])
      expect(title).to eq('untitled')
    end
  end

  describe '#system_generated?' do
    let(:exporter) { described_class.new(project_path, output_dir) }

    it 'identifies system-generated content' do
      expect(exporter.send(:system_generated?, '<system-reminder>Test</system-reminder>')).to be true
      expect(exporter.send(:system_generated?, '<command-name>test</command-name>')).to be true
      expect(exporter.send(:system_generated?, 'Regular user message')).to be false
    end
  end

  describe '#extract_text_content' do
    let(:exporter) { described_class.new(project_path, output_dir) }

    it 'extracts text from content array and formats tool use' do
      content_array = [
        { 'type' => 'text', 'text' => 'Hello there!' },
        { 'type' => 'tool_use', 'name' => 'some_tool', 'input' => { 'param' => 'value' } },
        { 'type' => 'tool_result', 'content' => 'Tool executed successfully' },
        { 'type' => 'text', 'text' => 'How can I help?' }
      ]
      
      result = exporter.send(:extract_text_content, content_array)
      expect(result).to include('Hello there!')
      expect(result).to include('How can I help?')
      expect(result).to include('## 🔧 Tool Use')
      expect(result).to include('<details>')
      expect(result).to include('<summary>some_tool</summary>')
      # Tool result is now handled at message pairing level, not content array level
      expect(result).to include('Tool executed successfully') # Still present as JSON
    end

    it 'handles tool_use without tool_result' do
      content_array = [
        { 'type' => 'tool_use', 'name' => 'some_tool', 'input' => { 'param' => 'value' } }
      ]
      
      result = exporter.send(:extract_text_content, content_array)
      expect(result).to include('## 🔧 Tool Use')
      expect(result).to include('<summary>some_tool</summary>')
      expect(result).not_to include('<summary>Tool Result</summary>')
    end

    it 'preserves non-text, non-tool content as JSON' do
      content_array = [
        { 'type' => 'image', 'data' => 'base64...' }
      ]
      
      result = exporter.send(:extract_text_content, content_array)
      expect(result).to include('image')
      expect(result).to include('base64...')
    end
  end

  describe '#format_tool_use' do
    let(:exporter) { described_class.new(project_path, output_dir) }

    it 'formats tool use with collapsed sections' do
      tool_use = {
        'name' => 'Read',
        'input' => { 'file_path' => '/path/to/file.txt' }
      }
      tool_result = {
        'content' => 'File contents here'
      }
      
      result = exporter.send(:format_tool_use, tool_use, tool_result)
      
      expect(result).to include('## 🔧 Tool Use')
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
      
      expect(result).to include('## 🔧 Tool Use')
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
      
      expect(result).to include('## 🔧 Tool Use')
      expect(result).to include('<summary>TodoWrite</summary>')
      expect(result).to include('✅ First task')
      expect(result).to include('🔄 Second task')
      expect(result).to include('⏳ Third task')
      expect(result).not_to include('```json')
    end
  end

  describe '#format_todo_list' do
    let(:exporter) { described_class.new(project_path, output_dir) }

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
  end

  describe '#extract_message with text extraction' do
    let(:exporter) { described_class.new(project_path, output_dir) }

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
      
      result = exporter.send(:extract_message, data, 0)
      expect(result[:content]).to include('Here is my response.')
      expect(result[:content]).to include('## 🔧 Tool Use')
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
      
      result = exporter.send(:extract_message, data, 0)
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

    before do
      File.write(session_file, jsonl_content)
      allow_any_instance_of(described_class).to receive(:system)
    end

    it 'provides class method for easy export' do
      allow(Dir).to receive(:pwd).and_return(project_path)
      result = described_class.export
      
      expect(result[:sessions_exported]).to be >= 0
      expect(result).to have_key(:total_messages)
    end
  end

  describe '#format_tool_use - enhanced formatting' do
    let(:exporter) { described_class.new('/test/project') }

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
    let(:exporter) { described_class.new('/test/project') }

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
    let(:exporter) { described_class.new }

    it 'does not filter out tool use content' do
      tool_content = '## 🔧 Tool Use\n<details>\n<summary>Write</summary>'
      
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
    let(:exporter) { described_class.new }

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
      
      result = exporter.send(:extract_message, data, 0)
      
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
      
      result = exporter.send(:extract_message, data, 0)
      
      expect(result[:tool_use_ids]).to eq(['tool123', 'tool456'])
    end
  end
end