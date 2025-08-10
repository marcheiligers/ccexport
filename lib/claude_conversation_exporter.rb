#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'time'
require 'set'

class ClaudeConversationExporter
  class << self
    def export(project_path = Dir.pwd, output_dir = 'claude-conversations', options = {})
      new(project_path, output_dir, options).export
    end
  end

  def initialize(project_path = Dir.pwd, output_dir = 'claude-conversations', options = {})
    @project_path = File.expand_path(project_path)
    @output_dir = File.expand_path(output_dir)
    @claude_home = find_claude_home
    @compacted_conversation_processed = false
    @options = options
    setup_date_filters
  end

  def export
    session_dir = find_session_directory
    session_files = Dir.glob(File.join(session_dir, '*.jsonl')).sort
    
    raise "No session files found in #{session_dir}" if session_files.empty?

    FileUtils.mkdir_p(@output_dir)
    
    puts "Found #{session_files.length} session file(s)"
    
    sessions = []
    total_messages = 0
    
    session_files.each do |session_file|
      session = process_session(session_file)
      next if session[:messages].empty?
      
      sessions << session
      puts "✓ #{session[:session_id]}: #{session[:messages].length} messages"
      total_messages += session[:messages].length
    end
    
    # Sort sessions by first timestamp to ensure chronological order
    sessions.sort_by! { |session| session[:first_timestamp] || '1970-01-01T00:00:00Z' }
    
    if sessions.empty?
      puts "\nNo sessions to export"
      return { sessions_exported: 0, total_messages: 0 }
    end
    
    # Generate combined output
    filename = generate_combined_filename(sessions)
    output_path = File.join(@output_dir, filename)
    
    File.write(output_path, format_combined_markdown(sessions))
    
    puts "\nExported #{sessions.length} conversations (#{total_messages} total messages) to #{output_path}"
    
    { sessions_exported: sessions.length, total_messages: total_messages }
  end

  private

  def setup_date_filters
    if @options[:today]
      # Filter for today only in user's timezone
      today = Time.now
      @from_time = Time.new(today.year, today.month, today.day, 0, 0, 0, today.utc_offset)
      @to_time = Time.new(today.year, today.month, today.day, 23, 59, 59, today.utc_offset)
    else
      if @options[:from]
        begin
          date = Date.parse(@options[:from])
          @from_time = Time.new(date.year, date.month, date.day, 0, 0, 0, Time.now.utc_offset)
        rescue ArgumentError
          raise "Invalid from date format: #{@options[:from]}. Use YYYY-MM-DD format."
        end
      end
      
      if @options[:to]
        begin
          date = Date.parse(@options[:to])
          @to_time = Time.new(date.year, date.month, date.day, 23, 59, 59, Time.now.utc_offset)
        rescue ArgumentError
          raise "Invalid to date format: #{@options[:to]}. Use YYYY-MM-DD format."
        end
      end
    end
  end

  def message_in_date_range?(timestamp)
    return true unless @from_time || @to_time
    
    begin
      message_time = Time.parse(timestamp)
      
      if @from_time && message_time < @from_time
        return false
      end
      
      if @to_time && message_time > @to_time
        return false
      end
      
      true
    rescue ArgumentError
      # If timestamp is invalid, include the message
      true
    end
  end

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
    messages = process_messages_linearly(session_file)
    
    {
      session_id: session_id,
      messages: messages,
      first_timestamp: messages.first&.dig(:timestamp),
      last_timestamp: messages.last&.dig(:timestamp)
    }
  end

  def process_messages_linearly(jsonl_file)
    messages = []
    pending_tool_use = nil
    
    File.readlines(jsonl_file, chomp: true).each_with_index do |line, index|
      next if line.strip.empty?
      
      begin
        data = JSON.parse(line)
        
        # Skip ignorable message types
        next if data.key?('isApiErrorMessage') || data.key?('leafUuid') || data.key?('isMeta')
        
        # Skip messages outside date range
        next unless message_in_date_range?(data['timestamp'])
        
        if data.key?('isCompactSummary')
          # Extract clean compacted conversation (only if first one)
          unless @compacted_conversation_processed
            messages << format_compacted_conversation(data)
            @compacted_conversation_processed = true
          end
        elsif data.key?('toolUseResult')
          # Pair with previous tool_use
          if pending_tool_use
            messages << format_combined_tool_use(pending_tool_use, data)
            pending_tool_use = nil
          end
        elsif data.key?('requestId') || regular_message?(data)
          # Check if this assistant message contains tool_use
          if tool_use_message?(data)
            pending_tool_use = data # Hold for pairing with next toolUseResult
          else
            message = format_regular_message(data)
            messages << message if message
          end
        end
      rescue JSON::ParserError => e
        puts "Warning: Skipping invalid JSON at line #{index + 1}: #{e.message}"
      end
    end
    
    messages
  end

  def regular_message?(data)
    # Messages without special keys are regular messages
    special_keys = %w[isApiErrorMessage leafUuid isMeta isCompactSummary requestId toolUseResult]
    special_keys.none? { |key| data.key?(key) }
  end

  def tool_use_message?(data)
    return false unless data['message']
    content = data['message']['content']
    return false unless content.is_a?(Array)
    
    content.any? { |item| item.is_a?(Hash) && item['type'] == 'tool_use' }
  end

  def format_compacted_conversation(data)
    content = data.dig('message', 'content')
    text = content.is_a?(Array) ? content.first['text'] : content
    
    {
      role: 'user',
      content: format_compacted_block(text),
      timestamp: data['timestamp'],
      index: 0
    }
  end

  def format_combined_tool_use(tool_use_data, tool_result_data)
    # Extract tool_use from assistant message
    tool_uses = tool_use_data.dig('message', 'content')&.select { |item| item['type'] == 'tool_use' }
    return nil unless tool_uses&.any?

    # Extract tool_result
    tool_result = tool_result_data.dig('message', 'content')&.first
    
    # Format as combined tool use + result
    content = format_tool_use(tool_uses.first, tool_result)
    
    {
      role: 'assistant',
      content: content,
      timestamp: tool_use_data['timestamp'],
      index: 0
    }
  end

  def format_thinking_message(data)
    thinking_content = data['thinking']
    
    # Format thinking content as blockquote
    thinking_lines = thinking_content.split("\n").map { |line| "> #{line}" }
    formatted_content = thinking_lines.join("\n")
    
    {
      role: 'assistant_thinking',
      content: formatted_content,
      timestamp: data['timestamp'] || Time.now.iso8601,
      index: 0
    }
  end

  def format_regular_message(data)
    role = data.dig('message', 'role')
    content = data.dig('message', 'content')
    
    return nil if system_generated_data?(data)
    
    if content.is_a?(Array)
      result = extract_text_content(content)
      processed_content = result[:content]
      has_thinking = result[:has_thinking]
      
      # Update role if message contains thinking
      role = 'assistant_thinking' if has_thinking && role == 'assistant'
    elsif content.is_a?(String)
      processed_content = content
    else
      processed_content = JSON.pretty_generate(content)
    end
    
    return nil if processed_content.strip.empty?
    
    # Skip messages that contain compacted conversation phrases
    # Only official isCompactSummary messages should contain these
    text_to_check = processed_content.to_s
    has_compacted_phrases = text_to_check.include?('Primary Request and Intent:') ||
                           text_to_check.include?('This session is being continued from a previous conversation')
    
    return nil if has_compacted_phrases
    
    {
      role: role,
      content: processed_content,
      timestamp: data['timestamp'],
      index: 0
    }
  end

  def system_generated_data?(data)
    content = data.dig('message', 'content')
    
    if content.is_a?(Array)
      text_content = content.select { |item| item['type'] == 'text' }.map { |item| item['text'] }.join(' ')
    elsif content.is_a?(String)
      text_content = content
    else
      return false
    end
    
    system_generated?(text_content)
  end

  # Test helper method - processes a single message data for testing
  def test_process_message(data, index = 0)
    # Skip ignorable message types
    return nil if data.key?('isApiErrorMessage') || data.key?('leafUuid') || data.key?('isMeta')
    
    if data['type'] == 'thinking'
      format_thinking_message(data)
    elsif data.key?('isCompactSummary')
      format_compacted_conversation(data)
    elsif data.key?('toolUseResult')
      # For testing, just return the tool result data
      {
        role: 'user',
        content: data.dig('message', 'content').to_s,
        timestamp: data['timestamp'],
        index: index,
        tool_result: true
      }
    elsif data.key?('requestId') || regular_message?(data)
      if tool_use_message?(data)
        # Extract tool_use_ids for testing
        content = data.dig('message', 'content')
        tool_use_ids = content.select { |item| item.is_a?(Hash) && item['type'] == 'tool_use' }
                              .map { |item| item['id'] }
        
        result = extract_text_content(content)
        
        # Return tool use message for testing
        {
          role: 'assistant',
          content: result[:content],
          timestamp: data['timestamp'],
          index: index,
          tool_use: true,
          tool_use_ids: tool_use_ids
        }
      else
        format_regular_message(data)
      end
    end
  end

  def extract_text_content(content_array)
    parts = []
    has_thinking = false
    
    content_array.each do |item|
      if item.is_a?(Hash) && item['type'] == 'text' && item['text']
        parts << item['text']
      elsif item.is_a?(Hash) && item['type'] == 'thinking' && item['thinking']
        # Format thinking content as blockquote
        thinking_lines = item['thinking'].split("\n").map { |line| "> #{line}" }
        parts << thinking_lines.join("\n")
        has_thinking = true
      elsif item.is_a?(Hash) && item['type'] == 'tool_use'
        # Format tool_use without tool_result (will be paired later at message level)
        parts << format_tool_use(item, nil)
      else
        # Preserve other content types as JSON for now
        parts << JSON.pretty_generate(item)
      end
    end
    
    # If this message contains thinking, it needs special role handling
    content = parts.join("\n\n")
    
    { content: content, has_thinking: has_thinking }
  end

  # Helper method to escape backticks in code blocks
  def escape_backticks(content)
    content.to_s.gsub('`', '\\`')
  end

  # Helper method to escape HTML tags
  def escape_html(content)
    content.to_s.gsub('&', '&amp;')
               .gsub('<', '&lt;')
               .gsub('>', '&gt;')
               .gsub('"', '&quot;')
               .gsub("'", '&#39;')
  end


  # Format any compacted conversation content as collapsible section
  def format_compacted_block(text)
    # Extract only the first/latest conversation summary to avoid repetition
    cleaned_text = extract_latest_conversation_summary(text)
    
    lines = []
    lines << "<details>"
    lines << "<summary>Compacted</summary>"
    lines << ""
    lines << escape_html(escape_backticks(cleaned_text))
    lines << "</details>"
    
    lines.join("\n")
  end
  
  # Extract the first complete conversation summary, removing nested repetitions
  def extract_latest_conversation_summary(text)
    # Very specific approach: extract just the clean Analysis section before any corruption
    if text.include?('This session is being continued from a previous conversation')
      
      # Find the Analysis section
      if text.include?('Analysis:')
        analysis_start = text.index('Analysis:')
        after_analysis = text[analysis_start..-1]
        
        # Look for the first signs of corruption/nesting in the analysis
        corruption_indicators = [
          'This session is being continued from a previous conversation',
          'toolu_',
          # Look for incomplete sentences that suggest corruption
          ' to '  # Often appears as "pointing to This session..."
        ]
        
        # Find the earliest corruption point
        earliest_corruption = nil
        corruption_indicators.each do |indicator|
          pos = after_analysis.index(indicator)
          if pos && (earliest_corruption.nil? || pos < earliest_corruption)
            earliest_corruption = pos
          end
        end
        
        if earliest_corruption
          # Take everything up to the corruption point
          clean_analysis_end = analysis_start + earliest_corruption
          clean_text = text[0...clean_analysis_end].strip
          
          # Make sure we end at a reasonable point
          if clean_text.end_with?(',') || clean_text.end_with?(' ')
            clean_text = clean_text.rstrip.chomp(',') + '.'
          elsif !clean_text.end_with?('.')
            clean_text += '.'
          end
          
          clean_text += "\n\n[Conversation summary continues with additional technical details and implementation steps...]"
          return clean_text
        else
          # No corruption found, but limit length anyway
          return text[0..2000].strip + "\n\n[Summary continues...]"
        end
      end
      
      # Fallback if no Analysis section
      return text[0..1000].strip + "\n\n[Summary abbreviated]"
    end
    
    # Final fallback
    text.length > 1000 ? text[0..1000] + "\n\n[Content truncated]" : text
  end

  def format_tool_use(tool_use, tool_result = nil)
    tool_name = tool_use['name'] || 'Unknown Tool'
    tool_input = tool_use['input'] || {}
    
    markdown = ["## 🤖🔧 Assistant"]
    
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
        markdown << escape_backticks(tool_input['content'])
        markdown << "```"
      else
        # Fallback to JSON if no content
        markdown << "```json"
        markdown << escape_backticks(JSON.pretty_generate(tool_input))
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
      markdown << escape_backticks(command)
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
        markdown << escape_backticks(tool_input['old_string'])
        markdown << "```"
        markdown << ""
        markdown << "**After:**"
        markdown << "```#{language}"
        markdown << escape_backticks(tool_input['new_string'])
        markdown << "```"
      else
        # Fallback to JSON if old_string/new_string not available
        markdown << "```json"
        markdown << escape_backticks(JSON.pretty_generate(tool_input))
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
      
      markdown << escape_backticks(result_content)
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
      
      lines << "#{status_emoji} #{todo['content']}  "
    end
    
    lines.join("\n")
  end


  def system_generated?(content)
    return false unless content.is_a?(String)
    
    # Skip tool use content - it's legitimate
    return false if content.start_with?('## 🤖🔧 Assistant')
    
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

  def generate_combined_filename(sessions)
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    
    if sessions.length == 1
      title = generate_title(sessions.first[:messages])
      "#{timestamp}-#{title}-#{sessions.first[:session_id]}.md"
    else
      first_session = sessions.first
      last_session = sessions.last
      title = generate_title(first_session[:messages])
      "#{timestamp}-#{title}-combined-#{sessions.length}-sessions.md"
    end
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

  def format_combined_markdown(sessions)
    md = []
    md << "# Claude Code Conversations"
    md << ""
    
    if sessions.length == 1
      # Single session - use original format
      return format_markdown(sessions.first)
    end
    
    # Multiple sessions - combined format
    total_messages = sessions.sum { |s| s[:messages].length }
    total_user = sessions.sum { |s| s[:messages].count { |m| m[:role] == 'user' } }
    total_assistant = sessions.sum { |s| s[:messages].count { |m| m[:role] == 'assistant' } }
    
    md << "**Sessions:** #{sessions.length}"
    md << "**Total Messages:** #{total_messages} (#{total_user} user, #{total_assistant} assistant)"
    md << ""
    
    first_timestamp = sessions.map { |s| s[:first_timestamp] }.compact.min
    last_timestamp = sessions.map { |s| s[:last_timestamp] }.compact.max
    
    if first_timestamp
      md << "**Started:** #{Time.parse(first_timestamp).getlocal.strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    if last_timestamp
      md << "**Last activity:** #{Time.parse(last_timestamp).getlocal.strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    md << ""
    md << "---"
    md << ""
    
    # Process each session with separators
    sessions.each_with_index do |session, session_index|
      unless session_index == 0
        md << ""
        md << "---"
        md << ""
        md << "# Session #{session_index + 1}"
        md << ""
        md << "**Session ID:** `#{session[:session_id]}`"
        
        if session[:first_timestamp]
          md << "**Started:** #{Time.parse(session[:first_timestamp]).getlocal.strftime('%B %d, %Y at %I:%M %p')}"
        end
        
        user_count = session[:messages].count { |m| m[:role] == 'user' }
        assistant_count = session[:messages].count { |m| m[:role] == 'assistant' }
        
        md << "**Messages:** #{session[:messages].length} (#{user_count} user, #{assistant_count} assistant)"
        md << ""
      end
      
      # Add messages for this session
      session[:messages].each_with_index do |message, index|
        md.concat(format_message(message, index + 1))
        md << "" unless index == session[:messages].length - 1
      end
    end
    
    # Replace all absolute project paths with relative paths in the final output
    make_paths_relative(md.join("\n"))
  end

  def format_markdown(session)
    md = []
    md << "# Claude Code Conversation"
    md << ""
    md << "**Session:** `#{session[:session_id]}`"
    md << ""
    
    if session[:first_timestamp]
      md << "**Started:** #{Time.parse(session[:first_timestamp]).getlocal.strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    if session[:last_timestamp]
      md << "**Last activity:** #{Time.parse(session[:last_timestamp]).getlocal.strftime('%B %d, %Y at %I:%M %p')}"
    end
    
    user_count = session[:messages].count { |m| m[:role] == 'user' }
    assistant_count = session[:messages].count { |m| m[:role] == 'assistant' }
    
    md << "**Messages:** #{session[:messages].length} (#{user_count} user, #{assistant_count} assistant)"
    md << ""
    md << "---"
    md << ""
    
    # Process messages linearly - they're already processed and paired
    session[:messages].each_with_index do |message, index|
      md.concat(format_message(message, index + 1))
      md << "" unless index == session[:messages].length - 1
    end
    
    # Replace all absolute project paths with relative paths in the final output
    make_paths_relative(md.join("\n"))
  end


  def format_message(message, number)
    lines = []
    
    # Check if message content starts with Tool Use heading
    skip_assistant_heading = message[:role] == 'assistant' && 
                            message[:content].start_with?('## 🤖🔧 Assistant')
    
    unless skip_assistant_heading
      case message[:role]
      when 'user'
        lines << "## 👤 User"
      when 'assistant'
        lines << "## 🤖 Assistant"
      when 'assistant_thinking'
        lines << "## 🤖💭 Assistant"
      when 'system'
        lines << "## ⚙️ System"
      end
      
      lines << ""
    end
    
    lines << message[:content]
    lines << ""
    
    lines
  end

  def make_paths_relative(content)
    # Replace absolute project paths with relative paths throughout the content
    content.gsub(@project_path + '/', '')
           .gsub(@project_path, '.')
  end
end