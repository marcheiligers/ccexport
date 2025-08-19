# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2024-08-17

### Added
- Initial release of ccexport gem
- Export Claude Code conversations from JSONL session files to Markdown and HTML
- Multiple HTML templates: default, github, solarized with dark/light mode support
- Comprehensive syntax highlighting with Prism.js for Ruby, JavaScript, Python, TypeScript, JSON, Markdown, YAML, Bash
- TruffleHog integration for secret detection and redaction
- Date filtering and custom output paths
- HTML preview generation with automatic browser opening
- Command-line interface with extensive options
- Support for both single session and multi-session exports
- Path relativization for project files
- Comprehensive test suite with RSpec