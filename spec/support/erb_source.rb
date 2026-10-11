# frozen_string_literal: true

require "rubocop/rspec/cop_helper"
require "rubocop/rspec/expect_offense"
require "rubocop/rspec/shared_contexts"

# CopHelper integrates the RuboCop plugins in the bundle (e.g. rubocop-rbs_inline) into the default
# configuration of the process. Skip it, or the plugins leak into the other specs running RuboCop
CopHelper.integrated_plugins = true

# Lets `expect_offense`, `expect_no_offenses`, `expect_correction` and `expect_no_corrections`
# parse the source as an ERB file through rubocop-herb, so that cops investigate the Ruby code
# converted from the ERB source and corrections are applied to the ERB source
RSpec.shared_context "with ERB source" do
  include CopHelper
  include RuboCop::RSpec::ExpectOffense

  include_context "config"

  before { RuboCop::Herb::Configuration.setup({}) }

  # The corrector of the last investigation, set by CopHelper#_investigate and read by RuboCop::RSpec::ExpectOffense
  attr_accessor :last_corrector

  # The ERB source is parsed as Ruby first, then converted by the Extractor
  # (which takes over the config and the registry of the processed source)
  def parse_source(source, file = nil)
    RuboCop::Herb::Extractor.call(super(source, file || "test.html.erb")).first[:processed_source]
  end

  # Cops correct the converted Ruby code, so import the correction into a buffer of the ERB source
  # as RuboCop::Cop::Team does for extracted sources
  def _investigate(cop, processed_source)
    offenses = super
    erb_buffer = Parser::Source::Buffer.new(processed_source.path, source: processed_source.parse_result.code)
    erb_corrector = RuboCop::Cop::Corrector.new(erb_buffer)
    erb_corrector.import!(last_corrector, offset: 0)
    self.last_corrector = erb_corrector
    offenses
  end
end
