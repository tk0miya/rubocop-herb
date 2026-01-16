# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "yaml"

RSpec.describe "Integration test with RuboCop", type: :feature do
  let(:runner) { RuboCop::Lsp::StdinRunner.new(config_store) }
  let(:config_store) do
    RuboCop::ConfigStore.new.tap do |store|
      store.options_config = config.path
    end
  end
  let(:config) do
    Tempfile.new([".rubocop", ".yml"]).tap do |f|
      f.write(YAML.dump(RuboCop::Herb::Configuration.to_rubocop_config))
      f.close
    end
  end
  let(:path) { "test.html.erb" }

  before do
    RuboCop::Herb::Configuration.setup({})
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
  end

  after do
    config.unlink
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  context "when analyzing an simple ERB file" do
    let(:source) { "<%= 'Hello world' %>" }

    it "detects offenses" do
      runner.run(path, source, {})
      offenses = runner.offenses.map(&:cop_name)
      expect(offenses).to eq []
    end
  end

  context "when analyzing if-else-end with output tags" do
    let(:source) do
      <<~ERB
        <% if condition %>
          <%= value1 %>
        <% else %>
          <%= value2 %>
        <% end %>
      ERB
    end

    it "does not trigger Style/ConditionalAssignment" do
      runner.run(path, source, {})
      offenses = runner.offenses.map(&:cop_name)
      expect(offenses).not_to include("Style/ConditionalAssignment")
    end
  end

  context "when analyzing each block with output tags" do
    let(:source) do
      <<~ERB
        <% items.each do |item| %>
          <%= item %>
        <% end %>
      ERB
    end

    it "does not trigger Lint/Void" do
      runner.run(path, source, {})
      offenses = runner.offenses.map(&:cop_name)
      expect(offenses).not_to include("Lint/Void")
    end
  end
end
