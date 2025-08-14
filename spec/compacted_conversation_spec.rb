require_relative 'spec_helper'
require 'tmpdir'

RSpec.describe 'Compacted Conversation Handling' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_dir) { File.join(temp_dir, 'output') }
  let(:exporter) { ClaudeConversationExporter.new(temp_dir, output_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe 'compacted conversation detection and processing' do
    let(:session_data) do
      [
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'content' => [{'type' => 'text', 'text' => 'This session is being continued from a previous conversation that ran out of context. The conversation is summarized below:\n1. Primary Request and Intent:\n   - Build something'}]
          },
          'isCompactSummary' => true
        },
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'content' => 'Normal user message without compacted content'
          }
        },
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'content' => 'Another message with Primary Request and Intent: embedded content'
          }
        },
        {
          'type' => 'assistant',
          'message' => {
            'role' => 'assistant',
            'content' => [{'type' => 'text', 'text' => 'Response with Primary Request and Intent: in the text'}]
          }
        }
      ]
    end

    it 'should only process one compacted conversation message' do
      # Create a temporary session file
      session_file = File.join(temp_dir, 'test-session.jsonl')
      File.write(session_file, session_data.map(&:to_json).join("\n"))

      # Mock the file finding methods
      allow(exporter).to receive(:find_session_directory).and_return(temp_dir)

      # Export and capture the result
      result = exporter.export

      # Check the output
      md_files = Dir.glob(File.join(output_dir, '*.md'))
      expect(md_files.length).to eq(1)

      content = File.read(md_files.first)

      # Should have exactly one compacted section
      compacted_count = content.scan(/Compacted<\/summary>/).length
      expect(compacted_count).to eq(1)

      # Should have exactly three occurrences of "Primary Request and Intent"
      # (one in compacted summary, one in user message, one in assistant message)
      primary_request_count = content.scan(/Primary Request and Intent/).length
      expect(primary_request_count).to eq(3)

      # Should have the normal user message
      expect(content).to include('Normal user message without compacted content')
    end
  end
end
