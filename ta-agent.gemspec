# frozen_string_literal: true

require_relative "lib/ta-agent/version"

Gem::Specification.new do |spec|
  spec.name = "ta-agent"
  spec.version = TaAgent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "CLI-first Technical Analysis Agent for Indian markets (NIFTY/options)"
  spec.description = <<~DESC
    A serious CLI-based Technical Analysis Agent for Indian markets, powered by
    dhanhq-client for data, deterministic TA pipelines (multi-timeframe), and
    optional LLM analysis via Ollama. Zero Rails, zero RSpec, zero UI.
    Designed for automation, cron jobs, and integration with trading systems.
  DESC
  spec.homepage = "https://github.com/shubhamtaywade/ta-agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies - minimal, intentional
  # Note: DhanHQ git source is specified in Gemfile for development
  # Gemspecs cannot use git: option - use version requirement here
  spec.add_dependency "tty-command", "~> 0.10"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-logger", "~> 0.6"
  spec.add_dependency "tty-config", "~> 0.6"
  spec.add_dependency "faraday", ">= 0.9", "< 3.0"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "ruby-technical-analysis", "~> 1.0", ">= 1.0.4"

  # No Rails
  # No RSpec
  # No ActiveSupport bloat
end
