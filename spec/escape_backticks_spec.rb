require_relative 'spec_helper'

RSpec.describe 'escape_backticks method' do
  let(:exporter) { create_silent_exporter }

  describe '#escape_backticks' do
    it 'should properly escape single backticks' do
      result = exporter.send(:escape_backticks, 'test `code` here')
      expect(result).to eq('test \\`code\\` here')
    end

    it 'should properly escape triple backticks' do
      result = exporter.send(:escape_backticks, '```javascript\ncode\n```')
      expect(result).to eq('\\`\\`\\`javascript\ncode\n\\`\\`\\`')
    end

    it 'should handle mixed backticks properly' do
      result = exporter.send(:escape_backticks, 'test `single` and ```triple``` backticks')
      expect(result).to eq('test \\`single\\` and \\`\\`\\`triple\\`\\`\\` backticks')
    end

    it 'should not corrupt the string with recursive replacements' do
      # This test demonstrates the current bug
      input = '```123```'
      result = exporter.send(:escape_backticks, input)
      
      # Should be: \`\`\`123\`\`\`
      # But currently produces: ```123```123```123````123``
      expect(result).to eq('\\`\\`\\`123\\`\\`\\`')
    end

    it 'should handle empty strings' do
      result = exporter.send(:escape_backticks, '')
      expect(result).to eq('')
    end

    it 'should handle strings with no backticks' do
      result = exporter.send(:escape_backticks, 'no backticks here')
      expect(result).to eq('no backticks here')
    end

    it 'should handle nil input' do
      result = exporter.send(:escape_backticks, nil)
      expect(result).to eq('')
    end
  end
end