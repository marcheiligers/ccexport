#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'time'

class ClaudeConversationExporter
  class << self
    def export(project_path = Dir.pwd, output_dir = 'claude-conversations')
      new(project_path, output_dir).export
    end
  end

  def initialize(project_path = Dir.pwd, output_dir = 'claude-conversations')
    @project_path = File.expand_path(project_path)
    @output_dir = File.expand_path(output_dir)
    @claude_home = find_claude_home
  end

  def export
    session_dir = find_session_directory
    session_files = Dir.glob(File.join(session_dir, '*.jsonl')).sort
    
    raise "No session files found in #{session_dir}" if session_files.empty?

    FileUtils.mkdir_p(@output_dir)
    
    puts "Found #{session_files.length} session file(s)"
    
    exported_count = 0
    total_messages = 0
    
    session_files.each do |session_file|
      session = process_session(session_file)
      next if session[:messages].empty?
      
      filename = generate_filename(session)
      output_path = File.join(@output_dir, filename)
      
      File.write(output_path, format_markdown(session))
      
      puts "✓ #{session[:session_id]}: #{session[:messages].length} messages"
      exported_count += 1
      total_messages += session[:messages].length
    end
    
    puts "\nExported #{exported_count} conversations (#{total_messages} total messages) to #{@output_dir}/"
    
    # Send notification as requested
    system("osascript -e \"display notification \\\"Exported #{exported_count} conversations\\\" sound name \\\"Ping\\\" with title \\\"Claude Code\\\"\"")
    
    { sessions_exported: exported_count, total_messages: total_messages }
  end

  private

  def find_claude_home
    candidates = [
      File.join(Dir.home, '.claude'),
      File.join(Dir.home, '.config', 'claude')
    ]
    
    claude_home = candidates.find { |path| Dir.exist?(File.join(path, 'projects')) }
    raise "Claude home directory not found. Searched: #{candidates.join(', ')}" unless claude_home
    
    claude_home
  end

  def find_session_directory
    encoded_path = encode_path(@project_path)
    session_dir = File.join(@claude_home, 'projects', encoded_path)
    
    return session_dir if Dir.exist?(session_dir)
    
    # Fallback: search for directories containing project name
    project_name = File.basename(@project_path)
    projects_dir = File.join(@claude_home, 'projects')
    
    candidates = Dir.entries(projects_dir)
                   .select { |dir| dir.include?(project_name) && Dir.exist?(File.join(projects_dir, dir)) }
                   .map { |dir| File.join(projects_dir, dir) }
    
    raise "No Claude sessions found for project: #{@project_path}" if candidates.empty?
    
    candidates.first
  end

  def encode_path(path)
    path.gsub('/', '-').gsub('_', '-')
  end

  def process_session(session_file)
    session_id = File.basename(session_file, '.jsonl')
    messages = []
    
    File.readlines(session_file, chomp: true).each_with_index do |line, index|
      next if line.strip.empty?
      
      begin
        data = JSON.parse(line)
        message = extract_message(data, index)
        messages << message if message
      rescue JSON::ParserError => e
        puts "Warning: Skipping invalid JSON at line #{index + 1}: #{e.message}"
      end
    end
    
    {
      session_id: session_id,
      messages: messages,
      first_timestamp: messages.first&.dig(:timestamp),
      last_timestamp: messages.last&.dig(:timestamp)
    }
  end

  def extract_message(data, index)
    return nil unless data['message'] && data['message']['role']
    
    role = data['message']['role']
    content = data['message']['content']
    
    # Extract tool IDs if this is an assistant message with tool_use
    tool_use_ids = []
    if role == 'assistant' && content.is_a?(Array)
      tool_use_ids = content.select { |item| item.is_a?(Hash) && item['type'] == 'tool_use' }
                            .map { |item| item['id'] }
    end
    
    # Extract text content for assistant responses
    processed_content = if role == 'assistant' && content.is_a?(Array)
                          extract_text_content(content)
                        elsif content.is_a?(String)
                          content
                        else
                          JSON.pretty_generate(content)
                        end
    
    # Handle tool calls and results
    tool_calls = extract_tool_calls(processed_content)
    tool_results = extract_tool_results(data)
    
    # Skip system-generated messages
    return nil if system_generated?(processed_content)
    
    # Skip messages with empty content unless they have tool_use
    return nil if processed_content.strip.empty? && tool_use_ids.empty?
    
    {
      role: role,
      content: processed_content,
      timestamp: data['timestamp'] || Time.now.iso8601,
      index: index,
      tool_calls: tool_calls,
      tool_results: tool_results,
      tool_use_ids: tool_use_ids
    }
  end

  def extract_text_content(content_array)
    parts = []
    
    content_array.each do |item|
      if item.is_a?(Hash) && item['type'] == 'text' && item['text']
        parts << item['text']
      elsif item.is_a?(Hash) && item['type'] == 'tool_use'
        # Format tool_use without tool_result (will be paired later at message level)
        parts << format_tool_use(item, nil)
      else
        # Preserve other content types as JSON for now
        parts << JSON.pretty_generate(item)
      end
    end
    
    parts.join("\n\n")
  end

  def format_tool_use(tool_use, tool_result = nil)
    tool_name = tool_use['name'] || 'Unknown Tool'
    tool_input = tool_use['input'] || {}
    
    markdown = ["## 🔧 Tool Use"]
    
    # Main collapsed section for the tool
    markdown << "<details>"
    
    # Special formatting for Write tool
    if tool_name == 'Write' && tool_input['file_path']
      # Extract relative path from the file_path
      relative_path = tool_input['file_path'].gsub(@project_path, '').gsub(/^\//, '')
      markdown << "<summary>Write #{relative_path}</summary>"
      markdown << ""
      
      # Format content in appropriate code block
      if tool_input['content']
        # Determine file extension for syntax highlighting
        extension = File.extname(tool_input['file_path']).downcase
        language = case extension
                   when '.rb'
                     'ruby'
                   when '.js'
                     'javascript'
                   when '.py'
                     'python'
                   when '.ts'
                     'typescript'
                   when '.json'
                     'json'
                   when '.md'
                     'markdown'
                   when '.yml', '.yaml'
                     'yaml'
                   when '.sh'
                     'bash'
                   else
                     ''
                   end
        
        markdown << "```#{language}"
        markdown << tool_input['content']
        markdown << "```"
      else
        # Fallback to JSON if no content
        markdown << "```json"
        markdown << JSON.pretty_generate(tool_input)
        markdown << "```"
      end
    # Special formatting for Bash tool
    elsif tool_name == 'Bash' && tool_input['command']
      description = tool_input['description'] || 'Run bash command'
      markdown << "<summary>Bash: #{description}</summary>"
      markdown << ""
      
      # Make paths relative in the command
      command = tool_input['command'].gsub(@project_path, '.').gsub(@project_path.gsub('/', '\\/'), '.')
      
      markdown << "```bash"
      markdown << command
      markdown << "```"
    # Special formatting for Edit tool
    elsif tool_name == 'Edit' && tool_input['file_path']
      # Extract relative path from the file_path
      relative_path = tool_input['file_path'].gsub(@project_path, '').gsub(/^\//, '')
      markdown << "<summary>Edit #{relative_path}</summary>"
      markdown << ""
      
      # Determine file extension for syntax highlighting
      extension = File.extname(tool_input['file_path']).downcase
      language = case extension
                 when '.rb'
                   'ruby'
                 when '.js'
                   'javascript'
                 when '.py'
                   'python'
                 when '.ts'
                   'typescript'
                 when '.json'
                   'json'
                 when '.md'
                   'markdown'
                 when '.yml', '.yaml'
                   'yaml'
                 when '.sh'
                   'bash'
                 else
                   ''
                 end
      
      if tool_input['old_string'] && tool_input['new_string']
        markdown << "**Before:**"
        markdown << "```#{language}"
        markdown << tool_input['old_string']
        markdown << "```"
        markdown << ""
        markdown << "**After:**"
        markdown << "```#{language}"
        markdown << tool_input['new_string']
        markdown << "```"
      else
        # Fallback to JSON if old_string/new_string not available
        markdown << "```json"
        markdown << JSON.pretty_generate(tool_input)
        markdown << "```"
      end
    # Special formatting for TodoWrite tool
    elsif tool_name == 'TodoWrite' && tool_input['todos']
      markdown << "<summary>#{tool_name}</summary>"
      markdown << ""
      markdown << format_todo_list(tool_input['todos'])
    else
      # Default JSON formatting for other tools
      markdown << "<summary>#{tool_name}</summary>"
      markdown << ""
      markdown << "```json"
      markdown << JSON.pretty_generate(tool_input)
      markdown << "```"
    end
    
    markdown << "</details>"
    
    # Separate collapsed section for tool result if available
    if tool_result
      markdown << ""
      markdown << "<details>"
      markdown << "<summary>Tool Result</summary>"
      markdown << ""
      markdown << "```"
      
      result_content = if tool_result['content'].is_a?(String)
                        tool_result['content']
                      else
                        JSON.pretty_generate(tool_result['content'])
                      end
      
      markdown << result_content
      markdown << "```"
      markdown << "</details>"
    end
    
    markdown.join("\n")
  end

  def format_todo_list(todos)
    lines = []
    
    todos.each do |todo|
      status_emoji = case todo['status']
                    when 'completed'
                      '✅'
                    when 'in_progress'
                      '🔄'
                    when 'pending'
                      '⏳'
                    else
                      '❓'
                    end
      
      lines << "#{status_emoji} #{todo['content']}"
    end
    
    lines.join("\n")
  end

  def extract_tool_calls(content)
    return [] unless content.is_a?(String)
    
    tool_calls = []
    content.scan(/<function_calls>(.*?)<\/antml:function_calls>/m) do |match|
      tool_calls << { type: 'function_calls', content: match[0].strip }
    end
    
    tool_calls
  end

  def extract_tool_results(data)
    return [] unless data['message'] && data['message']['content'].is_a?(Array)
    
    data['message']['content'].select { |item| item['type'] == 'tool_result' }
  end

  def system_generated?(content)
    return false unless content.is_a?(String)
    
    # Skip tool use content - it's legitimate
    return false if content.start_with?('## 🔧 Tool Use')
    
    skip_patterns = [
      'Caveat: The messages below were generated',
      '<command-name>',
      '<local-command-stdout>',
      '<local-command-stderr>',
      '<system-reminder>'
    ]
    
    skip_patterns.any? { |pattern| content.include?(pattern) }
  end

  def generate_filename(session)
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    title = generate_title(session[:messages])
    "#{timestamp}-#{title}-#{session[:session_id]}.md"
  end

  def generate_title(messages)
    first_user_message = messages.find { |m| m[:role] == 'user' }
    return 'untitled' unless first_user_message
    
    content = first_user_message[:content]
    title = content.split("\n").first.to_s
                  .gsub(/^(drop it\.?|real|actually|honestly)[\s,.]*/i, '')
                  .strip
                  .split(/[\s\/]+/)
                  .first(5)
                  .join('-')
                  .gsub(/[^a-zA-Z0-9-]/, '')
                  .downcase
    
    title.empty? ? 'untitled' : title[0, 50]
  end

  def format_markdown(session)
    md = []
    md << "# Claude Code Conversation"
    md << ""
    md << "**Session:** `#{session[:session_id]}`  "
    
    if session[:first_timestamp]
      md << "**Started:** #{Time.parse(session[:first_timestamp]).strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    if session[:last_timestamp]
      md << "**Last activity:** #{Time.parse(session[:last_timestamp]).strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    user_count = session[:messages].count { |m| m[:role] == 'user' }
    assistant_count = session[:messages].count { |m| m[:role] == 'assistant' }
    
    md << "**Messages:** #{session[:messages].length} (#{user_count} user, #{assistant_count} assistant)"
    md << ""
    md << "---"
    md << ""
    
    # Process messages with tool pairing
    processed_messages = process_tool_pairing(session[:messages])
    
    processed_messages.each_with_index do |message, index|
      next if message[:skip] # Skip tool_result messages that were paired
      
      md.concat(format_message(message, index + 1))
      md << "" unless index == processed_messages.length - 1
    end
    
    # Replace all absolute project paths with relative paths in the final output
    make_paths_relative(md.join("\n"))
  end

  def process_tool_pairing(messages)
    processed = messages.dup
    
    # Build a map of tool_use_id -> tool_result for efficient lookup
    tool_results_map = {}
    processed.each_with_index do |message, index|
      if message[:role] == 'user' && is_tool_result_message?(message[:content])
        tool_results = extract_tool_results_from_content(message[:content])
        tool_results.each do |result|
          tool_results_map[result['tool_use_id']] = {
            result: result,
            message_index: index
          }
        end
      end
    end
    
    # Process assistant messages to pair with tool results
    processed.each_with_index do |message, index|
      if message[:role] == 'assistant' && message[:content].include?('## 🔧 Tool Use')
        # Use stored tool IDs from the message
        tool_ids = message[:tool_use_ids] || []
        
        # Find matching tool results
        matching_results = []
        tool_ids.each do |tool_id|
          if tool_results_map[tool_id]
            matching_results << tool_results_map[tool_id][:result]
          end
        end
        
        # If we found matching results, add them to the assistant message
        if matching_results.any?
          processed[index] = message.merge(
            content: combine_tool_use_with_results(message[:content], matching_results)
          )
          
          # Mark the corresponding tool result messages to be skipped
          matching_results.each do |result|
            result_info = tool_results_map[result['tool_use_id']]
            result_message_index = result_info[:message_index]
            processed[result_message_index] = processed[result_message_index].merge(skip: true)
          end
        end
      end
    end
    
    processed
  end

  def is_tool_result_message?(content)
    # Check if content looks like a tool result array
    content.strip.start_with?('[') && content.include?('tool_result')
  end

  def extract_tool_results_from_content(content)
    begin
      parsed = JSON.parse(content)
      if parsed.is_a?(Array)
        parsed.select { |item| item['type'] == 'tool_result' }
      else
        []
      end
    rescue JSON::ParserError
      []
    end
  end


  def combine_tool_use_with_results(tool_use_content, tool_results)
    combined = tool_use_content.dup
    
    tool_results.each do |tool_result|
      combined += "\n\n<details>\n<summary>Tool Result</summary>\n\n```\n"
      combined += tool_result['content'].to_s
      combined += "\n```\n</details>"
    end
    
    combined
  end

  def format_message(message, number)
    lines = []
    
    # Check if message content starts with Tool Use heading
    skip_assistant_heading = message[:role] == 'assistant' && 
                            message[:content].start_with?('## 🔧 Tool Use')
    
    unless skip_assistant_heading
      case message[:role]
      when 'user'
        lines << "## 👤 User"
      when 'assistant'
        lines << "## 🤖 Assistant"
      when 'system'
        lines << "## ⚙️ System"
      end
      
      lines << ""
    end
    
    # Format tool calls if present
    if message[:tool_calls] && !message[:tool_calls].empty?
      lines << format_tool_calls(message[:content])
    else
      lines << message[:content]
    end
    
    lines << ""
    
    lines
  end

  def format_tool_calls(content)
    # Extract tool calls and format them nicely
    formatted = content.dup
    
    # Replace function_calls blocks with formatted versions
    formatted.gsub!(/<function_calls>(.*?)<\/antml:function_calls>/m) do |match|
      tool_content = $1.strip
      
      # Try to extract tool invocations
      tools = []
      tool_content.scan(/<invoke name="([^"]+)">(.*?)<\/antml:invoke>/m) do |tool_name, params|
        tools << { name: tool_name, params: params.strip }
      end
      
      if tools.any?
        tool_list = tools.map { |tool| "- **#{tool[:name]}**" }.join("\n")
        "**🔧 Tool calls:**\n#{tool_list}\n\n<details>\n<summary>View details</summary>\n\n```xml\n#{tool_content}\n```\n\n</details>"
      else
        "**🔧 Tool call:**\n\n```xml\n#{tool_content}\n```"
      end
    end
    
    formatted
  end

  def make_paths_relative(content)
    # Replace absolute project paths with relative paths throughout the content
    content.gsub(@project_path + '/', '')
           .gsub(@project_path, '.')
  end
end