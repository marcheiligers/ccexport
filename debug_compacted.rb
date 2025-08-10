#!/usr/bin/env ruby

require 'json'

# Analyze the compacted conversation issue
session_file = ARGV[0] || "/Users/marcheiligers/.claude/projects/-Users-marcheiligers-Projects-ccexport/237f049f-a9f9-47c3-8076-aa4126326b96.jsonl"

puts "Analyzing session file: #{File.basename(session_file)}"
puts "=" * 80

messages_with_phrase = []
total_messages = 0

File.readlines(session_file, chomp: true).each_with_index do |line, index|
  next if line.strip.empty?
  
  begin
    data = JSON.parse(line)
    total_messages += 1
    
    # Skip non-message entries
    next unless data['message'] && data['message']['role']
    
    role = data['message']['role']
    content = data['message']['content']
    is_compact_summary = data['isCompactSummary'] == true
    
    # Check if content contains the phrase
    text_to_check = if content.is_a?(Array)
                      content.map { |item| item['text'] || item.to_s }.join(' ')
                    else
                      content.to_s
                    end
    
    if text_to_check.include?('Primary Request and Intent:')
      messages_with_phrase << {
        line: index + 1,
        role: role,
        is_compact_summary: is_compact_summary,
        content_type: content.class.name,
        content_length: text_to_check.length,
        phrase_count: text_to_check.scan(/Primary Request and Intent:/).length,
        uuid: data['uuid']
      }
    end
  rescue JSON::ParserError => e
    puts "Warning: Invalid JSON at line #{index + 1}: #{e.message}"
  end
end

puts "Total messages: #{total_messages}"
puts "Messages containing 'Primary Request and Intent:': #{messages_with_phrase.length}"
puts "\nBreakdown:"
puts

messages_with_phrase.each_with_index do |msg, i|
  puts "#{i + 1}. Line #{msg[:line]} - #{msg[:role]} (#{msg[:content_type]})"
  puts "   Length: #{msg[:content_length]} chars"
  puts "   Phrase count: #{msg[:phrase_count]}"
  puts "   Compact summary: #{msg[:is_compact_summary]}"
  puts "   UUID: #{msg[:uuid]}"
  puts
end

puts "Summary:"
puts "- Official compact summaries: #{messages_with_phrase.count { |m| m[:is_compact_summary] }}"
puts "- User messages: #{messages_with_phrase.count { |m| m[:role] == 'user' }}"
puts "- Assistant messages: #{messages_with_phrase.count { |m| m[:role] == 'assistant' }}"
puts "- Total phrase occurrences: #{messages_with_phrase.sum { |m| m[:phrase_count] }}"