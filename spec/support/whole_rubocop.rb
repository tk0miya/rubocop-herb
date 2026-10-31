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
#
# `expect_correction` and `expect_no_corrections` check the source autocorrected by all cops, including
# unsafe ones (as `rubocop -A` does), after `expect_offense` or `expect_no_offenses`
#
# The `rubocop_config` metadata is merged into the default configuration, e.g. to enable a cop disabled by default:
#
#   context "with a cop disabled by default", rubocop_config: { "Style/Foo" => { "Enabled" => true } } do
#
# The `file_name` metadata changes the name of the linted file (default: `test.html.erb`):
#
#   context "with a file name containing a locale", file_name: "show.en-US.html.erb" do
RSpec.shared_context "with the whole RuboCop" do
  before { RuboCop::Herb::Configuration.setup({}) }

  # The source of the last `expect_offense` or `expect_no_offenses`, read by `expect_correction`
  attr_accessor :last_source

  def expect_offense(source)
    expected = RuboCop::RSpec::ExpectOffense::AnnotatedSource.parse(source)
    self.last_source = expected.plain_source
    actual = expected.with_offense_annotations(run_rubocop(last_source))
    expect(actual.to_s).to eq expected.to_s
  end

  def expect_no_offenses(source)
    self.last_source = source
    # Annotate the offenses in the source, so that any offense makes it differ from the source and shows
    # where it is reported. The source is not parsed for annotations, as it has none
    expected = RuboCop::RSpec::ExpectOffense::AnnotatedSource.new(source.each_line.to_a, [])
    actual = expected.with_offense_annotations(run_rubocop(source))
    expect(actual.to_s).to eq source
  end

  def expect_correction(correction, **options)
    raise "`expect_correction` must follow `expect_offense` or `expect_no_offenses`" unless last_source

    expect(autocorrect(last_source, **options)).to eq correction
  end

  def expect_no_corrections(**options)
    expect_correction(last_source, **options)
  end

  def run_rubocop(source)
    run(source, {}).offenses
  end

  def autocorrect(source, **options)
    run(source, { autocorrect: true, **options }).formatted_source
  end

  private

  def run(source, options)
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
    Tempfile.create([".rubocop", ".yml"]) do |config|
      config.write(YAML.dump(rubocop_config))
      config.close

      runner = RuboCop::Lsp::StdinRunner.new(RuboCop::ConfigStore.new.tap { _1.options_config = config.path })
      runner.run(RSpec.current_example.metadata.fetch(:file_name, "test.html.erb"), source, options)
      runner
    end
  ensure
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  def rubocop_config
    config = RuboCop::Herb::Configuration.to_rubocop_config
    config["AllCops"] = config["AllCops"].merge("NewCops" => "enable")
    # Herb/Linting is tested in herb_lint_spec.rb
    config["Herb/Linting"] = { "Enabled" => false }
    overrides = RSpec.current_example.metadata.fetch(:rubocop_config, {})
    config.merge(overrides) { |_cop, default, override| default.merge(override) }
  end
end
