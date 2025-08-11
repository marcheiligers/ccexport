class MarkdownCodeBlockParser
  attr_reader :markdown, :matches, :pairs, :blocks

  def initialize(markdown)
    @markdown = markdown
    @matches = []
    @pairs = []
    @blocks = []
  end

  def parse
    find_all_code_blocks
    pair_code_blocks
    build_block_structures
    detect_nesting
    self
  end

  private

  def find_all_code_blocks
    # Find all backtick sequences with their positions
    pattern = /(^|\n)(```+)([a-zA-Z0-9]*)?/

    @markdown.scan(pattern) do
      match = Regexp.last_match
      pos = match.begin(0)
      backticks = match[2]
      lang = match[3] unless match[3].nil? || match[3].empty?

      @matches << {
        pos: pos,
        ticks: backticks.length,
        lang: lang,
        full_match: match[0],
        index: @matches.length
      }
    end
  end

  def pair_code_blocks
    stack = []

    @matches.each_with_index do |match, i|
      # Heuristic 1: If it has a language specifier, it's definitely opening
      if match[:lang]
        stack.push(i)
        next
      end

      # Heuristic 2: Check if this could be a closing block
      if !stack.empty? && i > 0
        last_opener_idx = stack.last
        last_opener = @matches[last_opener_idx]

        # Get content between them
        content_start = last_opener[:pos] + last_opener[:full_match].length
        content_end = match[:pos]
        content_between = @markdown[content_start...content_end].strip

        # If there's substantial content and tick counts match, likely a pair
        if content_between.length > 10 && last_opener[:ticks] == match[:ticks]
          @pairs << [last_opener_idx, i]
          stack.pop
          next
        end
      end

      # Heuristic 3: Check if this looks like an opening based on what follows
      if i < @matches.length - 1
        next_match = @matches[i + 1]
        content_after_end = next_match ? next_match[:pos] : @markdown.length
        content_after = @markdown[(match[:pos] + match[:full_match].length)...content_after_end].strip

        # If there's content after that looks like code, this might be opening
        if !content_after.empty? && !content_after.start_with?('#')
          stack.push(i)
          next
        end
      end

      # Default: assume it's closing if we have something to close
      if !stack.empty?
        # Try to match with the most recent opener with same tick count
        matched = false
        stack.reverse_each.with_index do |stack_idx, j|
          if @matches[stack_idx][:ticks] == match[:ticks]
            @pairs << [stack_idx, i]
            stack.delete_at(stack.length - 1 - j)
            matched = true
            break
          end
        end

        # No matching tick count, close the most recent
        if !matched
          @pairs << [stack.last, i]
          stack.pop
        end
      end
    end
  end

  def build_block_structures
    @pairs.each do |start_idx, end_idx|
      start_match = @matches[start_idx]
      end_match = @matches[end_idx]

      block = {
        start_pos: start_match[:pos],
        end_pos: end_match[:pos] + end_match[:full_match].length,
        language: start_match[:lang],
        tick_count: start_match[:ticks],
        content_start: start_match[:pos] + start_match[:full_match].length,
        content_end: end_match[:pos],
        start_match_idx: start_idx,
        end_match_idx: end_idx
      }

      # Extract content
      block[:content] = @markdown[block[:content_start]...block[:content_end]].strip

      @blocks << block
    end
  end

  def detect_nesting
    @blocks.each_with_index do |block, i|
      block[:nested_blocks] = []
      block[:depth] = 0

      @blocks.each_with_index do |other, j|
        next if i == j

        # Check if other is nested inside block
        if block[:start_pos] < other[:start_pos] && other[:end_pos] < block[:end_pos]
          block[:nested_blocks] << j
        end

        # Check if block is nested inside other
        if other[:start_pos] < block[:start_pos] && block[:end_pos] < other[:end_pos]
          block[:depth] += 1
        end
      end
    end
  end

  def escape_nested_blocks
    # Calculate maximum nesting depth
    max_depth = @blocks.map { |b| b[:depth] }.max || 0

    # Create a list of modifications to apply
    modifications = []

    @blocks.each do |block|
      # Use 3 + (max_depth - depth) backticks
      # So the outermost uses the most backticks
      new_tick_count = 3 + (max_depth - block[:depth])
      old_tick_count = block[:tick_count]

      if new_tick_count != old_tick_count
        # Record the modification for the opening backticks
        start_match = @matches[block[:start_match_idx]]
        modifications << {
          pos: start_match[:pos],
          old_text: start_match[:full_match],
          new_text: start_match[:full_match].gsub('`' * old_tick_count, '`' * new_tick_count)
        }

        # Record the modification for the closing backticks
        end_match = @matches[block[:end_match_idx]]
        modifications << {
          pos: end_match[:pos],
          old_text: end_match[:full_match],
          new_text: end_match[:full_match].gsub('`' * old_tick_count, '`' * new_tick_count)
        }
      end
    end

    # Sort modifications by position (reverse order to maintain positions)
    modifications.sort_by! { |m| -m[:pos] }

    # Apply modifications
    result = @markdown.dup
    modifications.each do |mod|
      result[mod[:pos], mod[:old_text].length] = mod[:new_text]
    end

    result
  end

  public
  
  def display_analysis
    puts "Detected #{@matches.length} code block delimiters"
    puts "Formed #{@pairs.length} pairs"
    puts "\nCode blocks found:"

    @blocks.each_with_index do |block, i|
      puts "\nBlock #{i}:"
      puts "  Language: #{block[:language] || 'none'}"
      puts "  Position: #{block[:start_pos]}-#{block[:end_pos]}"
      puts "  Tick count: #{block[:tick_count]}"
      puts "  Nesting depth: #{block[:depth]}"
      puts "  Contains blocks: #{block[:nested_blocks].join(', ')}" unless block[:nested_blocks].empty?

      content_preview = block[:content][0..80].gsub(/\n/, ' ')
      puts "  Content preview: #{content_preview}..."
    end
  end
end

# Example usage
if __FILE__ == $0
  example = <<~MARKDOWN
    Perfect! I've successfully implemented the tool use formatting with collapsed sections as requested. Here's what I implemented:

    **Key Features:**

    1. **Tool Use Detection**: The code now detects `tool_use` entries in assistant message content arrays
    2. **Tool Pairing**: When a `tool_use` is found, it looks for the immediately following `tool_result` and pairs them together
    3. **Collapsed Sections**: Uses GitHub's `<details>/<summary>` tags from the cheatsheet
    4. **Formatted Output**: Each tool use gets:
       - A "## Tool Use" header
       - A collapsed section with the tool name as the summary
       - Input parameters displayed in a JSON code block
       - A nested collapsed section for tool results (if present)

    **Example Output:**
    ```markdown
    ## Tool Use
    <details>
    <summary>Read</summary>

    ```json
    {
      "file_path": "/path/to/file.txt"
    }
    ```

    <details>
    <summary>Tool Result</summary>

    ```
    File contents here
    ```
    </details>
    </details>
    ```

    **Test Coverage:**
    - All 20 tests pass
    - Tests verify tool use formatting with and without results
    - Tests ensure text content is still extracted cleanly
    - Tests confirm non-text content is preserved appropriately

    The tool use sections are now cleanly formatted with collapsible sections that show the tool name prominently and hide the technical details until clicked. Ready to continue customizing the formatting further!
  MARKDOWN

  parser = MarkdownCodeBlockParser.new(example)
  parser.parse
  parser.display_analysis

  puts "\n" + "="*50
  puts "Escaped version:"
  puts "="*50
  puts parser.escape_nested_blocks
end
