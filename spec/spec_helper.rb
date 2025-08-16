require_relative '../lib/claude_conversation_exporter'

# Helper method to create exporter with silent mode for tests
def create_silent_exporter(project_path = Dir.pwd, output_dir = 'claude-conversations', options = {})
  ClaudeConversationExporter.new(project_path, output_dir, options.merge(silent: true))
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    # mocks.allow_message_expectations_on_nil = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
