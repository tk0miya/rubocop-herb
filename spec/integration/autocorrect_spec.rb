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

  shared_examples "an ERB autocorrector" do
    it "corrects the offense while producing valid ERB" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq expected
      expect { ERB.new(runner.formatted_source) }.not_to raise_error
    end
  end

  context "with Layout/SpaceAroundOperators offense" do
    let(:source) { "<div><%= x==1 %></div>" }
    let(:expected) { "<div><%= x == 1 %></div>" }

    it_behaves_like "an ERB autocorrector"
  end

  context "with Style/StringConcatenation offense" do
    let(:source) { "<p><%= 'Hello' + 'World' %></p>" }
    let(:expected) { "<p><%= 'HelloWorld' %></p>" }

    it_behaves_like "an ERB autocorrector"
  end

  context "with Style/ZeroLengthPredicate offense" do
    let(:source) { "<%= arr.length==0 %>" }
    let(:expected) { "<%= arr.empty? %>" }

    it_behaves_like "an ERB autocorrector"
  end

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

    it_behaves_like "an ERB autocorrector"
  end

  context "with Style/EmptyElse offense whose correction removes only ERB tags" do
    let(:source) do
      <<~ERB
        <% if a %>
          <p>a</p>
        <% else %>
        <% end %>
      ERB
    end
    let(:expected) do
      <<~ERB
        <% if a %>
          <p>a</p>
        <% end %>
      ERB
    end

    it_behaves_like "an ERB autocorrector"
  end

  context "with Lint/LiteralAsCondition offense whose correction would remove HTML" do
    let(:source) do
      <<~ERB
        <% if true %>
          <p>a</p>
        <% end %>
      ERB
    end

    it "keeps the source unchanged" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq source
    end
  end

  context "with Style/UnlessElse offense whose correction would move HTML" do
    let(:source) do
      <<~ERB
        <% unless a %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
      ERB
    end

    it "keeps the source unchanged" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq source
    end
  end
end
