# frozen_string_literal: true

require_relative "lib/rubocop/herb/version"

Gem::Specification.new do |spec|
  spec.name = "rubocop-herb"
  spec.version = RuboCop::Herb::VERSION
  spec.authors = ["Takeshi KOMIYA"]
  spec.email = ["i.tkomiya@gmail.com"]

  spec.summary = "RuboCop plugin for HTML + ERB files"
  spec.description = "RuboCop plugin for HTML + ERB files"
  spec.homepage = "https://github.com/tk0miya/rubocop-herb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # LintRoller plugin metadata for RuboCop integration
  spec.metadata["default_lint_roller_plugin"] = "RuboCop::Herb::Plugin"

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

  spec.add_dependency "herb", ">= 0.8.0"
  spec.add_dependency "lint_roller", ">= 1.1.0"
end
