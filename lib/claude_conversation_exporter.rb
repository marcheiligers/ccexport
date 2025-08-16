#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'time'
require 'set'
require 'erb'
require 'open3'
require_relative 'secret_detector'

class ClaudeConversationExporter
  class << self
    def export(project_path = Dir.pwd, output_dir = 'claude-conversations', options = {})
      new(project_path, output_dir, options).export
    end

    def generate_preview(output_path_or_dir, open_browser = true, leaf_summaries = [], template_name = 'default', silent = false)
      # Helper method for output
      output_helper = lambda { |message| puts message unless silent }

      # Handle both directory and specific file paths
      if output_path_or_dir.end_with?('.md') && File.exist?(output_path_or_dir)
        # Specific markdown file provided
        latest_md = output_path_or_dir
        output_dir = File.dirname(output_path_or_dir)
      else
        # Directory provided - find the latest markdown file
        output_dir = output_path_or_dir
        latest_md = Dir.glob(File.join(output_dir, '*.md')).sort.last
      end

      if latest_md.nil? || !File.exist?(latest_md)
        output_helper.call "No markdown files found in #{output_dir}/"
        return false
      end

      output_helper.call "Creating preview for: #{File.basename(latest_md)}"

      # Check if cmark-gfm is available
      unless system('which cmark-gfm > /dev/null 2>&1')
        output_helper.call "Error: cmark-gfm not found. Install it with:"
        output_helper.call "  brew install cmark-gfm"
        return false
      end

      # Use cmark-gfm to convert markdown to HTML with --unsafe for collapsed sections
      # The --unsafe flag prevents escaping in code blocks
      stdout, stderr, status = Open3.capture3(
        'cmark-gfm', '--unsafe', '--extension', 'table', '--extension', 'strikethrough',
        '--extension', 'autolink', '--extension', 'tagfilter', '--extension', 'tasklist',
        latest_md
      )

      unless status.success?
        output_helper.call "Error running cmark-gfm: #{stderr}"
        return false
      end

      md_html = stdout

      # Load ERB template - support both template names and file paths
      if template_name.include?('/') || template_name.end_with?('.erb')
        # Full path provided
        template_path = template_name
      else
        # Template name provided - look in templates directory
        template_path = File.join(File.dirname(__FILE__), 'templates', "#{template_name}.html.erb")
      end
      unless File.exist?(template_path)
        output_helper.call "Error: ERB template not found at #{template_path}"
        return false
      end

      template = File.read(template_path)
      erb = ERB.new(template)

      # Create the complete HTML content using ERB template
      content = md_html
      title = extract_title_from_summaries_or_markdown(latest_md, leaf_summaries)
      full_html = erb.result(binding)

      # Create HTML file in output directory
      html_filename = latest_md.gsub(/\.md$/, '.html')
      File.write(html_filename, full_html)

      output_helper.call "HTML preview: #{html_filename}"

      # Open in the default browser only if requested
      if open_browser
        system("open", html_filename)
        output_helper.call "Opening in browser..."
      end

      html_filename
    end

    def include_prism
      # Prism.js CSS and JavaScript for syntax highlighting
      # MIT License - https://github.com/PrismJS/prism
      css = File.read(File.join(__dir__, 'assets/prism.css'))
      js = File.read(File.join(__dir__, 'assets/prism.js'))

      # Add initialization code to automatically highlight code blocks
      init_js = <<~JS

        /* Initialize Prism.js */
        if (typeof window !== 'undefined' && window.document) {
            document.addEventListener('DOMContentLoaded', function() {
                if (typeof Prism !== 'undefined' && Prism.highlightAll) {
                    Prism.highlightAll();
                }
            });
        }
      JS

      # Return both CSS and JS as a complete block
      "<style>#{css}</style>\n<script>#{js}#{init_js}</script>"
    end

    def extract_title_from_summaries_or_markdown(markdown_file, leaf_summaries = [])
      # Try to get title from leaf summaries first
      if leaf_summaries.any?
        # Use the first (oldest) summary as the main title
        return leaf_summaries.first[:summary]
      end

      # Fallback: read the markdown file and extract title from content
      begin
        content = File.read(markdown_file)

        # Look for the first user message content as fallback
        if content.match(/## 👤 User\s*\n\n(.+?)(?:\n\n|$)/m)
          first_user_message = $1.strip
          # Clean up the message for use as title
          title_words = first_user_message.split(/\s+/).first(8).join(' ')
          return title_words.length > 60 ? title_words[0..57] + '...' : title_words
        end

        # Final fallback
        "Claude Code Conversation"
      rescue
        "Claude Code Conversation"
      end
    end
  end

  def initialize(project_path = Dir.pwd, output_dir = 'claude-conversations', options = {})
    @project_path = File.expand_path(project_path)
    @output_dir = File.expand_path(output_dir)
    @claude_home = find_claude_home
    @compacted_conversation_processed = false
    @options = options
    @show_timestamps = options[:timestamps] || false
    @silent = options[:silent] || false
    @leaf_summaries = []
    @skipped_messages = []
    @secrets_detected = []
    setup_date_filters
    setup_secret_detection
  end

  def export
    if @options[:jsonl]
      # Process specific JSONL file
      session_files = [File.expand_path(@options[:jsonl])]
      session_dir = File.dirname(session_files.first)
    else
      # Scan for session files in directory
      session_dir = find_session_directory
      session_files = Dir.glob(File.join(session_dir, '*.jsonl')).sort
      raise "No session files found in #{session_dir}" if session_files.empty?
    end

    # Handle output path - could be a directory or specific file
    if @output_dir.end_with?('.md')
      # Specific file path provided
      output_path = File.expand_path(@output_dir)
      output_dir = File.dirname(output_path)
      FileUtils.mkdir_p(output_dir)
    else
      # Directory provided
      FileUtils.mkdir_p(@output_dir)
      output_dir = @output_dir
      output_path = nil  # Will be generated later
    end

    if @options[:jsonl]
      output "Processing specific JSONL file: #{File.basename(session_files.first)}"
    else
      output "Found #{session_files.length} session file(s) in #{session_dir}"
    end

    sessions = []
    total_messages = 0

    session_files.each do |session_file|
      session = process_session(session_file)
      next if session[:messages].empty?

      sessions << session
      output "✓ #{session[:session_id]}: #{session[:messages].length} messages"
      total_messages += session[:messages].length
    end

    # Sort sessions by first timestamp to ensure chronological order
    sessions.sort_by! { |session| session[:first_timestamp] || '1970-01-01T00:00:00Z' }

    if sessions.empty?
      output "\nNo sessions to export"
      return { sessions_exported: 0, total_messages: 0 }
    end

    # Generate output path if not already specified
    if output_path.nil?
      filename = generate_combined_filename(sessions)
      output_path = File.join(output_dir, filename)
    end

    File.write(output_path, format_combined_markdown(sessions))

    # Write skip log if there were any skipped messages
    write_skip_log(output_path)

    # Write secrets detection log if any secrets were detected
    write_secrets_log(output_path)

    output "\nExported #{sessions.length} conversations (#{total_messages} total messages) to #{output_path}"

    { sessions_exported: sessions.length, total_messages: total_messages, leaf_summaries: @leaf_summaries, output_file: output_path }
  end

  private


  def output(message)
    puts message unless @silent
  end

  def detect_language_from_path(file_path)
    return '' if file_path.nil? || file_path.empty?

    file_ext = File.extname(file_path).downcase
    file_name = File.basename(file_path)

    case file_ext
    when '.rb' then 'ruby'
    when '.js' then 'javascript'
    when '.ts' then 'typescript'
    when '.py' then 'python'
    when '.java' then 'java'
    when '.cpp', '.cc', '.cxx' then 'cpp'
    when '.c' then 'c'
    when '.h' then 'c'
    when '.html' then 'html'
    when '.css' then 'css'
    when '.scss' then 'scss'
    when '.json' then 'json'
    when '.yaml', '.yml' then 'yaml'
    when '.xml' then 'xml'
    when '.md' then 'markdown'
    when '.sh' then 'bash'
    when '.sql' then 'sql'
    else
      # Check common file names without extensions
      case file_name.downcase
      when 'gemfile', 'rakefile', 'guardfile', 'capfile', 'vagrantfile' then 'ruby'
      when 'makefile' then 'makefile'
      when 'dockerfile' then 'dockerfile'
      else ''
      end
    end
  end

  def track_skipped_message(line_index, reason, data = nil)
    return if reason == 'outside date range' # Don't log date range skips

    skip_entry = {
      line: line_index + 1,
      reason: reason
    }

    # Include the full JSON data if available
    skip_entry[:data] = data if data

    @skipped_messages << skip_entry
  end

  def write_skip_log(output_path)
    return if @skipped_messages.empty?

    log_path = output_path.gsub(/\.md$/, '_skipped.jsonl')

    File.open(log_path, 'w') do |f|
      @skipped_messages.each do |skip|
        f.puts JSON.generate(skip)
      end
    end

    output "Skipped #{@skipped_messages.length} messages (see #{File.basename(log_path)})"
  end

  def write_secrets_log(output_path)
    return if @secrets_detected.empty?

    log_path = output_path.gsub(/\.md$/, '_secrets.jsonl')

    File.open(log_path, 'w') do |f|
      @secrets_detected.each do |secret|
        f.puts JSON.generate(secret)
      end
    end

    output "⚠️  Detected #{@secrets_detected.length} potential secrets in conversation content (see #{File.basename(log_path)})"
    output "   Please review and ensure no sensitive information is shared in exports."
  end

  def setup_secret_detection
    # Initialize our custom secret detector
    @secret_detector = SecretDetector.new
  rescue StandardError => e
    output "Warning: Secret detection initialization failed: #{e.message}"
    output "Proceeding without secret detection."
    @secret_detector = nil
  end

  def setup_date_filters
    if @options[:today]
      # Filter for today only in user's timezone
      today = Time.now
      @from_time = Time.new(today.year, today.month, today.day, 0, 0, 0, today.utc_offset)
      @to_time = Time.new(today.year, today.month, today.day, 23, 59, 59, today.utc_offset)
    else
      if @options[:from]
        @from_time = parse_date_input(@options[:from], 'from', start_of_day: true)
      end

      if @options[:to]
        @to_time = parse_date_input(@options[:to], 'to', start_of_day: false)
      end
    end
  end

  def parse_date_input(date_input, param_name, start_of_day:)
    begin
      # Try timestamp format first (from --timestamps output)
      if date_input.match?(/\w+ \d{1,2}, \d{4} at \d{1,2}:\d{2}:\d{2} (AM|PM)/)
        parsed_time = Time.parse(date_input)
        return parsed_time
      end

      # Try YYYY-MM-DD format
      date = Date.parse(date_input)
      hour = start_of_day ? 0 : 23
      minute = start_of_day ? 0 : 59
      second = start_of_day ? 0 : 59

      Time.new(date.year, date.month, date.day, hour, minute, second, Time.now.utc_offset)
    rescue ArgumentError
      raise "Invalid #{param_name} date format: #{date_input}. Use YYYY-MM-DD or 'Month DD, YYYY at HH:MM:SS AM/PM' format."
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

        # Skip ignorable message types, but collect leaf summaries first
        if data.key?('leafUuid')
          extract_leaf_summary(data)
          track_skipped_message(index, 'leaf summary message', data)
          next
        end

        if data.key?('isApiErrorMessage') || data.key?('isMeta')
          track_skipped_message(index, 'api error or meta message', data)
          next
        end

        # Skip messages outside date range
        unless message_in_date_range?(data['timestamp'])
          track_skipped_message(index, 'outside date range', data)
          next
        end

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
            if message
              messages << message
            else
              track_skipped_message(index, 'empty or system-generated message', data)
            end
          end
        end
      rescue JSON::ParserError => e
        track_skipped_message(index, "invalid JSON: #{e.message}", nil)
        output "Warning: Skipping invalid JSON at line #{index + 1}: #{e.message}"
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
      message_id: data.dig('message', 'id'),
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
      message_id: tool_use_data.dig('message', 'id'),
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
      message_id: data.dig('message', 'id'),
      index: 0
    }
  end

  def format_regular_message(data)
    role = data.dig('message', 'role')
    content = data.dig('message', 'content')

    return nil if system_generated_data?(data)

    message_id = data.dig('message', 'id') || 'unknown'

    if content.is_a?(Array)
      result = extract_text_content(content, "message_#{message_id}")
      processed_content = result[:content]
      has_thinking = result[:has_thinking]

      # Update role if message contains thinking
      role = 'assistant_thinking' if has_thinking && role == 'assistant'
    elsif content.is_a?(String)
      # Scan and redact secrets from string content
      processed_content = scan_and_redact_secrets(content, "message_#{message_id}_string")
    else
      processed_content = JSON.pretty_generate(content)
    end

    return nil if processed_content.strip.empty?

    # Fix nested backticks in regular content
    processed_content = fix_nested_backticks_in_content(processed_content)

    # Skip messages that contain compacted conversation phrases
    # Only official isCompactSummary messages should contain these
    # text_to_check = processed_content.to_s
    # has_compacted_phrases = text_to_check.include?('Primary Request and Intent:') ||
    #                        text_to_check.include?('This session is being continued from a previous conversation')

    # return nil if has_compacted_phrases

    {
      role: role,
      content: processed_content,
      timestamp: data['timestamp'],
      message_id: data.dig('message', 'id'),
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
    # Skip ignorable message types, but collect leaf summaries first
    if data.key?('leafUuid')
      extract_leaf_summary(data)
      return nil
    end
    return nil if data.key?('isApiErrorMessage') || data.key?('isMeta')

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

        result = extract_text_content(content, "tool_use_#{data['uuid'] || 'unknown'}")

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

  def extract_text_content(content_array, context_id = 'content')
    parts = []
    has_thinking = false

    content_array.each do |item|
      if item.is_a?(Hash) && item['type'] == 'text' && item['text']
        # Scan and redact secrets from text content
        redacted_text = scan_and_redact_secrets(item['text'], "#{context_id}_text")
        parts << redacted_text
      elsif item.is_a?(Hash) && item['type'] == 'thinking' && item['thinking']
        # Scan and redact secrets from thinking content
        redacted_thinking = scan_and_redact_secrets(item['thinking'], "#{context_id}_thinking")
        # Format thinking content as blockquote
        thinking_lines = redacted_thinking.split("\n").map { |line| "> #{line}" }
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

  # Scan content for secrets and redact them using our custom detector
  def scan_and_redact_secrets(content, context_id = 'unknown')
    return content if @secret_detector.nil? || content.nil? || content.empty?

    original_content = content.to_s

    # Scan for secrets
    findings = @secret_detector.scan(original_content)

    # If no secrets found, return original content
    return content if findings.empty?

    # Record detected secrets for logging
    findings.each do |finding|
      @secrets_detected << {
        context: context_id,
        type: finding.type,
        pattern: finding.pattern_name,
        confidence: finding.confidence
      }
    end

    # Redact the secrets
    redacted_content = @secret_detector.redact(original_content)

    redacted_content
  rescue StandardError => e
    output "Warning: Secret detection/redaction failed for #{context_id}: #{e.message}"
    content
  end


  # Helper method to escape backticks in code blocks
  def escape_backticks(content)
    content.to_s.gsub('`', '\\\`')
  end

  # Helper method to escape HTML tags
  def escape_html(content)
    content.to_s.gsub('&', '&amp;')
               .gsub('<', '&lt;')
               .gsub('>', '&gt;')
               .gsub('"', '&quot;')
               .gsub("'", '&#39;')
  end

  # Helper method to determine how many backticks are needed to wrap content
  def determine_backticks_needed(content)
    # Find the longest sequence of consecutive backticks in the content
    max_backticks = content.scan(/`+/).map(&:length).max || 0

    # Use one more than the maximum found, with a minimum of 3
    needed = [max_backticks + 1, 3].max
    '`' * needed
  end

  # Helper method to escape content for code blocks (combines both escaping approaches)
  def escape_for_code_block(content)
    # First escape HTML entities, but don't escape backticks since we're handling them
    # with dynamic backtick counts
    # escape_html(content)
    content
  end

  # Fix nested backticks in regular message content
  def fix_nested_backticks_in_content(content)
    require_relative 'markdown_code_block_parser'

    parser = MarkdownCodeBlockParser.new(content)
    parser.parse

    # Use Opus's parser to escape nested blocks
    # Even though the pairing isn't perfect, it produces balanced HTML
    parser.send(:escape_nested_blocks)
  end


  # Format any compacted conversation content as collapsible section
  def format_compacted_block(text)
    lines = []
    lines << "<details>"
    lines << "<summary>Compacted</summary>"
    lines << ""
    lines << escape_html(escape_backticks(text))
    lines << "</details>"

    lines.join("\n")
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
        language = detect_language_from_path(tool_input['file_path'])

        # Use appropriate number of backticks to wrap content that may contain backticks
        backticks = determine_backticks_needed(tool_input['content'])
        markdown << "#{backticks}#{language}"
        markdown << escape_for_code_block(tool_input['content'])
        markdown << backticks
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

      backticks = determine_backticks_needed(command)
      markdown << "#{backticks}bash"
      markdown << escape_for_code_block(command)
      markdown << backticks
    # Special formatting for Edit tool
    elsif tool_name == 'Edit' && tool_input['file_path']
      # Extract relative path from the file_path
      relative_path = tool_input['file_path'].gsub(@project_path, '').gsub(/^\//, '')
      markdown << "<summary>Edit #{relative_path}</summary>"
      markdown << ""

      # Determine file extension for syntax highlighting
      language = detect_language_from_path(tool_input['file_path'])

      if tool_input['old_string'] && tool_input['new_string']
        old_backticks = determine_backticks_needed(tool_input['old_string'])
        new_backticks = determine_backticks_needed(tool_input['new_string'])

        markdown << "**Before:**"
        markdown << "#{old_backticks}#{language}"
        markdown << escape_for_code_block(tool_input['old_string'])
        markdown << old_backticks
        markdown << ""
        markdown << "**After:**"
        markdown << "#{new_backticks}#{language}"
        markdown << escape_for_code_block(tool_input['new_string'])
        markdown << new_backticks
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
    # Special formatting for Write tool to unescape content
    elsif tool_name == 'Write' && tool_input['content']
      markdown << "<summary>#{tool_name}: #{tool_input['file_path']}</summary>"
      markdown << ""
      if tool_input['content'].is_a?(String)
        # Detect language from file extension and common file names
        language = detect_language_from_path(tool_input['file_path'])

        markdown << "```#{language}"
        # Unescape the JSON string content
        unescaped_content = tool_input['content'].gsub('\\n', "\n").gsub('\\t', "\t").gsub('\\"', '"').gsub('\\\\', '\\')
        markdown << escape_backticks(unescaped_content)
        markdown << "```"
      else
        markdown << "```json"
        markdown << JSON.pretty_generate(tool_input)
        markdown << "```"
      end
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
    title = get_markdown_title
    md << "# #{title}"
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
    title = get_markdown_title
    md << "# #{title}"
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
      # Format role header with optional timestamp
      role_header = case message[:role]
                   when 'user'
                     "## 👤 User"
                   when 'assistant'
                     "## 🤖 Assistant"
                   when 'assistant_thinking'
                     "## 🤖💭 Assistant"
                   when 'system'
                     "## ⚙️ System"
                   end

      # Add timestamp if requested and available
      if @show_timestamps && message[:timestamp]
        begin
          local_time = Time.parse(message[:timestamp]).getlocal
          timestamp_str = local_time.strftime('%B %d, %Y at %I:%M:%S %p')
          role_header += " - #{timestamp_str}"
        rescue ArgumentError
          # Skip timestamp if parsing fails
        end
      end

      lines << role_header

      # Add message ID as HTML comment if available
      if message[:message_id]
        lines << "<!-- #{message[:message_id]} -->"
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

  def extract_leaf_summary(data)
    # Extract summary from leafUuid JSONL lines
    if data['leafUuid'] && data['summary']
      @leaf_summaries << {
        uuid: data['leafUuid'],
        summary: data['summary'],
        timestamp: data['timestamp']
      }
    end
  end

  def get_markdown_title
    # Use the first leaf summary as the markdown title
    if @leaf_summaries.any?
      return @leaf_summaries.first[:summary]
    end

    # Fallback titles
    "Claude Code Conversation"
  end

end
