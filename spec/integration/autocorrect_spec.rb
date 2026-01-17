# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "yaml"

RSpec.describe "Autocorrect with RuboCop", type: :feature do
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

  context "with Layout/SpaceAroundOperators offense" do
    let(:source) { "<div><%= x==1 %></div>" }

    it "corrects the offense" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq "<div><%= x == 1 %></div>"
    end

    it "produces valid ERB" do
      runner.run(path, source, { autocorrect: true })
      expect { ERB.new(runner.formatted_source) }.not_to raise_error
    end
  end

  context "with Style/StringConcatenation offense" do
    let(:source) { "<p><%= 'Hello' + 'World' %></p>" }

    it "corrects the offense" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq "<p><%= 'HelloWorld' %></p>"
    end

    it "produces valid ERB" do
      runner.run(path, source, { autocorrect: true })
      expect { ERB.new(runner.formatted_source) }.not_to raise_error
    end
  end

  context "with Style/ZeroLengthPredicate offense" do
    let(:source) { "<%= arr.length==0 %>" }

    it "corrects the offense" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq "<%= arr.empty? %>"
    end

    it "produces valid ERB" do
      runner.run(path, source, { autocorrect: true })
      expect { ERB.new(runner.formatted_source) }.not_to raise_error
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  context "with Layout/HashAlignment offense spanning multiple lines" do
    let(:source) do
      <<~ERB
        <%= render locals: {
          foo: 1,
          barbaz:   2
        } %>
      ERB
    end
    let(:expected) do
      <<~ERB
        <%= render locals: {
          foo: 1,
          barbaz: 2
        } %>
      ERB
    end

    it "corrects the offense" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq expected
    end

    it "produces valid ERB" do
      runner.run(path, source, { autocorrect: true })
      expect { ERB.new(runner.formatted_source) }.not_to raise_error
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
