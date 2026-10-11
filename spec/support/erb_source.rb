# frozen_string_literal: true

require "rubocop/rspec/cop_helper"
require "rubocop/rspec/expect_offense"
require "rubocop/rspec/shared_contexts"

# CopHelper integrates the RuboCop plugins in the bundle (e.g. rubocop-rbs_inline) into the default
# configuration of the process. Skip it, or the plugins leak into the other specs running RuboCop
CopHelper.integrated_plugins = true

# Lets `expect_offense` and `expect_no_offenses` parse the source as an ERB file through rubocop-herb,
# so that cops investigate the Ruby code converted from the ERB source
RSpec.shared_context "with ERB source" do
  include CopHelper
  include RuboCop::RSpec::ExpectOffense

  include_context "config"

  before { RuboCop::Herb::Configuration.setup({}) }

  # The ERB source is parsed as Ruby first, then converted by the Extractor
  # (which takes over the config and the registry of the processed source)
  def parse_source(source, file = nil)
    RuboCop::Herb::Extractor.call(super(source, file || "test.html.erb")).first[:processed_source]
  end
end
