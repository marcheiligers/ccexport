require 'json'
require 'tempfile'

class TruffleHogSecretDetector
  class Finding
    attr_reader :type, :pattern_name, :match, :detector_name, :verified, :line
    
    def initialize(detector_name, match, verified, line = nil)
      @type = 'secret'
      @pattern_name = detector_name
      @detector_name = detector_name
      @match = match
      @verified = verified
      @line = line
    end
    
    # For backward compatibility with old SecretDetector interface
    alias_method :confidence, :verified
  end
  
  def initialize
    # Check if trufflehog is available
    unless system('which trufflehog > /dev/null 2>&1')
      raise "TruffleHog not found. Install it with: brew install trufflehog"
    end
  end
  
  def scan(text)
    return [] if text.nil? || text.empty?
    
    findings = []
    
    # Create a temporary file with the text
    Tempfile.create(['trufflehog_scan', '.txt']) do |temp_file|
      temp_file.write(text)
      temp_file.flush
      
      # Run trufflehog on the temporary file
      output = `trufflehog filesystem --json --no-verification #{temp_file.path} 2>/dev/null`
      
      # Parse each line of JSON output
      output.each_line do |line|
        line = line.strip
        next if line.empty?
        
        begin
          result = JSON.parse(line)
          # Skip non-detection results (like log messages)
          next unless result['DetectorName'] && result['Raw']
          
          findings << Finding.new(
            result['DetectorName'],
            result['Raw'],
            result['Verified'] || false,
            result.dig('SourceMetadata', 'Data', 'Filesystem', 'line')
          )
        rescue JSON::ParserError
          # Skip malformed JSON lines
          next
        end
      end
    end
    
    findings
  end
  
  def redact(text, replacement = '[REDACTED]')
    return text if text.nil? || text.empty?
    
    findings = scan(text)
    return text if findings.empty?
    
    redacted_text = text.dup
    
    # Sort findings by match length (longest first) to avoid partial replacements
    findings.sort_by { |f| -f.match.length }.each do |finding|
      redacted_text = redacted_text.gsub(finding.match, replacement)
    end
    
    redacted_text
  end
  
  def has_secrets?(text)
    !scan(text).empty?
  end
end

# Alias for backward compatibility
SecretDetector = TruffleHogSecretDetector