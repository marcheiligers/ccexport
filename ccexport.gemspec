# frozen_string_literal: true

require_relative "lib/ccexport/version"

Gem::Specification.new do |spec|
  spec.name = "ccexport"
  spec.version = CcExport::VERSION
  spec.authors = ["Marc Heiligers"]
  spec.email = ["marc@silvermerc.net"]

  spec.summary = "Export and preview Claude Code conversations with syntax highlighting"
  spec.description = <<~DESC
    A Ruby tool to export Claude Code conversations from JSONL session files 
    into beautifully formatted Markdown and HTML files with syntax highlighting, 
    secret detection, and multiple template options.
  DESC
  spec.homepage = "https://github.com/marcheiligers/ccexport"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}.git"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/fetch_secrets_patterns spec/ VIBE claude-conversations/ debug_compacted.rb discover_structure.out discover_structure.rb generate_vibe_samples]) ||
        f.end_with?('.gem')
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "json", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"

  # Specify the minimum version of RubyGems required
  spec.required_rubygems_version = ">= 1.8.11"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end