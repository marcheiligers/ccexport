require_relative 'spec_helper'
require 'tmpdir'

RSpec.describe 'Secret Detection Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_dir) { File.join(temp_dir, 'output') }
  let(:exporter) { create_silent_exporter(temp_dir, output_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe 'secret detection in conversations' do
    let(:session_data) do
      [
        {
          'type' => 'user',
          'message' => {
            'role' => 'user',
            'id' => 'msg_test_user',
            'content' => 'Here is my GitHub token: ghp_1234567890123456789012345678901234567890 and AWS credentials: AKIA1234567890123456 secret: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
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
                'text' => 'I see you shared a Slack webhook: https://hooks.slack.com/services/T1234567890/B1234567890/abcdefghijklmnopqrstuvwx'
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
      expect(md_content).to include('[REDACTED]')  # Should contain masked secrets
      expect(md_content).not_to include('ghp_1234567890123456789012345678901234567890')  # Should not contain original GitHub token
      expect(md_content).not_to include('AKIA1234567890123456')  # Should not contain original AWS access key
      expect(md_content).not_to include('https://hooks.slack.com/services/T1234567890/B1234567890/abcdefghijklmnopqrstuvwx')  # Should not contain original Slack webhook
      
      # Check for secrets log file
      secrets_log_files = Dir.glob(File.join(output_dir, '*_secrets.jsonl'))
      expect(secrets_log_files.length).to eq(1)
      
      # Read and verify secrets log content
      secrets_log = File.read(secrets_log_files.first)
      secrets = secrets_log.split("\n").map { |line| JSON.parse(line) }
      
      expect(secrets.length).to be >= 3  # Should detect GitHub, AWS, and Slack secrets
      
      # Verify basic structure of detected secrets
      secrets.each do |secret|
        expect(secret['context']).to be_a(String)
        expect(secret['type']).to be_a(String)
        expect(secret['pattern']).to be_a(String)
        # TruffleHog uses boolean for verified status
        expect([true, false]).to include(secret['confidence'])
      end
      
      # Should detect GitHub, AWS, and Slack secrets
      has_github = secrets.any? { |s| s['pattern'].downcase.include?('github') }
      has_aws = secrets.any? { |s| s['pattern'].downcase.include?('aws') }
      has_slack = secrets.any? { |s| s['pattern'].downcase.include?('slack') }
      
      expect(has_github).to be true
      expect(has_aws).to be true
      expect(has_slack).to be true
      
      # Verify context information - secrets should be found in appropriate messages
      user_secrets = secrets.select { |s| s['context'].include?('message_msg_test_user') }
      assistant_secrets = secrets.select { |s| s['context'].include?('message_msg_test_assistant') }
      
      expect(user_secrets.length).to be >= 2  # GitHub + AWS from user message
      expect(assistant_secrets.length).to be >= 1  # Slack webhook from assistant message
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
      test_content = 'GitHub token: ghp_1234567890123456789012345678901234567890 AWS: AKIA1234567890123456 secret: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY Slack: https://hooks.slack.com/services/T1234567890/B1234567890/abcdefghijklmnopqrstuvwx'
      
      result = exporter.send(:scan_and_redact_secrets, test_content, 'test')
      
      # Content should be redacted (secrets masked)
      expect(result).not_to eq(test_content)
      expect(result).to include('[REDACTED]')  # Should contain masked content
      expect(result).not_to include('ghp_1234567890123456789012345678901234567890')  # Should not contain original GitHub token
      expect(result).not_to include('AKIA1234567890123456')  # Should not contain original AWS access key
      expect(result).not_to include('https://hooks.slack.com/services/T1234567890/B1234567890/abcdefghijklmnopqrstuvwx')  # Should not contain original Slack webhook
      
      # Should have detected the secrets
      secrets_detected = exporter.instance_variable_get(:@secrets_detected)
      expect(secrets_detected.length).to be >= 3
      
      # Verify different secret types were detected
      has_github = secrets_detected.any? { |s| s[:pattern].downcase.include?('github') }
      has_aws = secrets_detected.any? { |s| s[:pattern].downcase.include?('aws') }
      has_slack = secrets_detected.any? { |s| s[:pattern].downcase.include?('slack') }
      
      expect(has_github).to be true
      expect(has_aws).to be true  
      expect(has_slack).to be true
    end

    it 'should handle empty or nil content gracefully' do
      expect(exporter.send(:scan_and_redact_secrets, nil, 'test')).to be_nil
      expect(exporter.send(:scan_and_redact_secrets, '', 'test')).to eq('')
      expect(exporter.send(:scan_and_redact_secrets, '   ', 'test')).to eq('   ')
    end
  end
end