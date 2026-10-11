# frozen_string_literal: true

require "rubocop/lsp/stdin_runner"
require "rubocop/rspec/expect_offense"
require "tempfile"
require "yaml"

# Runs the whole RuboCop on the ERB source through rubocop-herb, enabling pending cops as users do with
# `NewCops: enable`, so that the specs do not hide false positives of any cop.
#
# `expect_offense` and `expect_no_offenses` check the offenses of all cops as RuboCop's ones do for a
# single cop. The messages in the annotations are prefixed with the cop names (e.g. `Style/UnlessElse: ...`)
RSpec.shared_context "with the whole RuboCop" do
  before { RuboCop::Herb::Configuration.setup({}) }

  def expect_offense(source)
    expected = RuboCop::RSpec::ExpectOffense::AnnotatedSource.parse(source)
    actual = expected.with_offense_annotations(run_rubocop(expected.plain_source))
    expect(actual.to_s).to eq expected.to_s
  end

  def expect_no_offenses(source)
    # Annotate the offenses in the source, so that any offense makes it differ from the source and shows
    # where it is reported. The source is not parsed for annotations, as it has none
    expected = RuboCop::RSpec::ExpectOffense::AnnotatedSource.new(source.each_line.to_a, [])
    actual = expected.with_offense_annotations(run_rubocop(source))
    expect(actual.to_s).to eq source
  end

  def run_rubocop(source)
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
    Tempfile.create([".rubocop", ".yml"]) do |config|
      config.write(YAML.dump(rubocop_config))
      config.close

      runner = RuboCop::Lsp::StdinRunner.new(RuboCop::ConfigStore.new.tap { _1.options_config = config.path })
      runner.run("test.html.erb", source, {})
      runner.offenses
    end
  ensure
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  def rubocop_config
    config = RuboCop::Herb::Configuration.to_rubocop_config
    config["AllCops"] = config["AllCops"].merge("NewCops" => "enable")
    # Herb/Linting is tested in herb_lint_spec.rb
    config["Herb/Linting"] = { "Enabled" => false }
    config
  end
end
