# Quick and dirty script to explore the structure of the jsonl files.

require 'json'

patterns = Hash.new { |h, k| h[k] = [] }

Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      patterns[json.keys.sort.join(',')] << line
    end
  end
end

puts "Unique sets of top-level keys"
puts patterns.keys.sort
puts '-' * 100

puts "isApiErrorMessage"
count = 0
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('isApiErrorMessage')
        puts JSON.pretty_generate(json) if count < 3
        count += 1
      end
    end
  end
end
puts "count: #{count}"
puts "NOTE: there's only 2 of these, one with true and one with false. they can be ignored."
puts '-' * 100

puts "leafUuid"
count = 0
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('leafUuid')
        puts JSON.pretty_generate(json) if count < 1
        count += 1
      end
    end
  end
end
puts 'NOTE: there are 3 of these, i think one in each session. they can be ignored.'
puts "count: #{count}"
puts '-' * 100

puts "isMeta"
count = 0
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('isMeta')
        puts JSON.pretty_generate(json) if count < 1
        count += 1
      end
    end
  end
end
puts "count: #{count}"
puts 'NOTE: there are a few of these. they can be ignored.'
puts '-' * 100

puts "isCompactSummary"
count = 0
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('isCompactSummary')
        puts JSON.pretty_generate(json) if count < 1
        count += 1
      end
    end
  end
end
puts "count: #{count}"
puts 'NOTE: these are the compaction summaries. these contain the **only** content that should be in the compaction summary'
puts '-' * 100

puts "requestId"
count = 0
roles = Hash.new { |h, k| h[k] = 0 }
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('requestId')
        puts JSON.pretty_generate(json) if count <= 5
        roles[json.dig('message', 'role')] += 1
        count += 1
      end
    end
  end
end
puts "count: #{count}"
puts "role counts: #{roles.to_json}"
puts 'NOTE: these look like normal messages'
puts '-' * 100

puts "toolUseResult"
count = 0
roles = Hash.new { |h, k| h[k] = 0 }
prev = {}
all = true
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if json.key?('toolUseResult')
        puts JSON.pretty_generate(json) if count <= 5
        roles[json.dig('message', 'role')] += 1
        count += 1
        all ||= prev.dig('message', 'content', 'type') == 'tool_use'
      end
    end
  end
end
puts "count: #{count}"
puts "role counts: #{roles.to_json}"
puts 'NOTE: are the results for tool use'
puts "is every toolUseResult preceeded by a tool_use? #{all}"
puts '-' * 100

puts "rest => has none of these keys: isApiErrorMessage, leafUuid, isMeta, isCompactSummary, requestId, toolUseResult"
count = 0
roles = Hash.new { |h, k| h[k] = 0 }
rest = %w[isApiErrorMessage leafUuid isMeta isCompactSummary requestId toolUseResult]
Dir.glob('spec/fixtures/*.jsonl') do |path|
  File.open(path) do |file|
    file.each_line do |line|
      json = JSON.parse(line)
      if rest.none? { |key| json.key?(key) }
        puts JSON.pretty_generate(json) if count <= 10
        roles[json.dig('message', 'role')] += 1
        count += 1
      end
    end
  end
end
puts "count: #{count}"
puts "role counts: #{roles.to_json}"
puts 'NOTE: these look like normal messages'
puts '-' * 100

