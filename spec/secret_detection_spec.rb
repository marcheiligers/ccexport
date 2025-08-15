require_relative 'spec_helper'
require 'tmpdir'

RSpec.describe 'Secret Detection Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_dir) { File.join(temp_dir, 'output') }
  let(:exporter) { ClaudeConversationExporter.new(temp_dir, output_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe 'secret detection in conversations' do
    let(:session_data) do
      [
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'id' => 'msg_test_user',
            'content' => 'Here is my AWS key: AKIAIOSFODNN7EXAMPLE'
          }
        },
        {
          'type' => 'assistant',
          'message' => {
            'role' => 'assistant',
            'id' => 'msg_test_assistant',
            'content' => [
              {
                'type' => 'text',
                'text' => 'I see you shared a Slack token: xoxb-1234567890-1234567890123-abcdefghijklmnop'
              }
            ]
          }
        }
      ]
    end

    it 'should detect secrets in conversation content and create a secrets log' do
      # Create a temporary session file
      session_file = File.join(temp_dir, 'test-session.jsonl')
      File.write(session_file, session_data.map(&:to_json).join("\n"))
      
      # Mock the file finding methods
      allow(exporter).to receive(:find_session_directory).and_return(temp_dir)
      
      # Export and capture the result
      result = exporter.export
      
      # Check the output files
      md_files = Dir.glob(File.join(output_dir, '*.md'))
      expect(md_files.length).to eq(1)
      
      # Verify that the exported markdown has redacted content
      md_content = File.read(md_files.first)
      expect(md_content).to include('*****')  # Should contain masked secrets
      expect(md_content).not_to include('AKIAIOSFODNN7EXAMPLE')  # Should not contain original AWS key
      expect(md_content).not_to include('xoxb-1234567890-1234567890123-abcdefghijklmnop')  # Should not contain original Slack token
      
      # Check for secrets log file
      secrets_log_files = Dir.glob(File.join(output_dir, '*_secrets.jsonl'))
      expect(secrets_log_files.length).to eq(1)
      
      # Read and verify secrets log content
      secrets_log = File.read(secrets_log_files.first)
      secrets = secrets_log.split("\n").map { |line| JSON.parse(line) }
      
      expect(secrets.length).to eq(2)  # Should detect both AWS and Slack tokens
      
      # Verify basic structure of detected secrets
      secrets.each do |secret|
        expect(secret['context']).to be_a(String)
        expect(secret['type']).to be_a(String)
        expect(secret['description']).to be_a(String)
        expect(secret['line']).to be_a(Integer)
      end
      
      # Should detect both AWS and Slack tokens
      has_aws = secrets.any? { |s| s['type'].downcase.include?('aws') }
      has_slack = secrets.any? { |s| s['type'].downcase.include?('slack') }
      expect(has_aws).to be true
      expect(has_slack).to be true
      
      # Verify context information
      aws_secret = secrets.find { |s| s['type'].downcase.include?('aws') }
      slack_secret = secrets.find { |s| s['type'].downcase.include?('slack') }
      
      expect(aws_secret['context']).to include('message_msg_test_user')
      expect(slack_secret['context']).to include('message_msg_test_assistant')
    end

    it 'should not create secrets log when no secrets are detected' do
      clean_session_data = [
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'id' => 'msg_clean',
            'content' => 'This is a clean message with no secrets'
          }
        }
      ]
      
      # Create a temporary session file
      session_file = File.join(temp_dir, 'clean-session.jsonl')
      File.write(session_file, clean_session_data.map(&:to_json).join("\n"))
      
      # Mock the file finding methods
      allow(exporter).to receive(:find_session_directory).and_return(temp_dir)
      
      # Export and capture the result
      result = exporter.export
      
      # Check that no secrets log was created
      secrets_log_files = Dir.glob(File.join(output_dir, '*_secrets.jsonl'))
      expect(secrets_log_files.length).to eq(0)
    end
  end

  describe 'secret detection methods' do
    it 'should detect and redact secrets in text content' do
      test_content = 'AWS key: AKIAIOSFODNN7EXAMPLE'
      
      result = exporter.send(:scan_and_redact_secrets, test_content, 'test')
      
      # Content should be redacted (secrets masked)
      expect(result).not_to eq(test_content)
      expect(result).to include('AWS key:')
      expect(result).to include('*****')  # Should contain masked content
      expect(result).not_to include('AKIAIOSFODNN7EXAMPLE')  # Should not contain original secret
      
      # Should have detected the secret
      secrets_detected = exporter.instance_variable_get(:@secrets_detected)
      expect(secrets_detected.length).to be >= 1
      
      aws_secret = secrets_detected.find { |s| s[:type].downcase.include?('aws') }
      expect(aws_secret).not_to be_nil
      expect(aws_secret[:context]).to eq('test')
    end

    it 'should handle empty or nil content gracefully' do
      expect(exporter.send(:scan_and_redact_secrets, nil, 'test')).to be_nil
      expect(exporter.send(:scan_and_redact_secrets, '', 'test')).to eq('')
      expect(exporter.send(:scan_and_redact_secrets, '   ', 'test')).to eq('   ')
    end
  end
end