require_relative '../lib/claude_conversation_exporter'
require 'json'

RSpec.describe 'Backticks fix' do
  let(:exporter) { create_silent_exporter }

  describe '#fix_nested_backticks_in_content' do
    it 'fixes markdown blocks containing nested backticks from the fixture' do
      # Load the actual problematic fixture
      fixture_path = 'spec/fixtures/backticks-in-backticks.json'
      fixture_data = JSON.parse(File.read(fixture_path))
      original_content = fixture_data['message']['content'][0]['text']

      # Process it through the fix
      fixed_content = exporter.send(:fix_nested_backticks_in_content, original_content)

      # The markdown block should now use 4+ backticks instead of 3
      expect(fixed_content).to include('````markdown')
      expect(fixed_content).to include('````')
      
      # The inner content should be preserved
      expect(fixed_content).to include('```json')
      expect(fixed_content).to include('File contents here')
    end

    it 'generates valid HTML from fixed content' do
      # Load the problematic fixture  
      fixture_path = 'spec/fixtures/backticks-in-backticks.json'
      fixture_data = JSON.parse(File.read(fixture_path))
      original_content = fixture_data['message']['content'][0]['text']

      # Process it through the fix
      fixed_content = exporter.send(:fix_nested_backticks_in_content, original_content)

      # Convert to HTML using cmark-gfm
      require 'open3'
      html_output, stderr, status = Open3.capture3('cmark-gfm', '--unsafe', stdin_data: fixed_content)

      # Should convert successfully without errors
      expect(status.success?).to be true
      expect(stderr).to be_empty

      # HTML should not contain broken/unclosed code blocks
      # Count opening and closing <pre><code> tags - they should match
      opening_code_blocks = html_output.scan(/<pre><code/).length
      closing_code_blocks = html_output.scan(/<\/code><\/pre>/).length
      
      expect(opening_code_blocks).to eq(closing_code_blocks), 
        "Mismatched code blocks: #{opening_code_blocks} opening vs #{closing_code_blocks} closing"

      # Should contain the expected structured content  
      expect(html_output).to include('&lt;summary&gt;Read&lt;/summary&gt;')
      expect(html_output).to include('File contents here')
      expect(html_output).to include('&quot;file_path&quot;')
    end
  end
end