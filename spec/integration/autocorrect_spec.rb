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
      f.write(YAML.dump(rubocop_config))
      f.close
    end
  end
  # Herb/Lint is tested in herb_lint_spec.rb
  let(:rubocop_config) { RuboCop::Herb::Configuration.to_rubocop_config.merge("Herb/Lint" => { "Enabled" => false }) }
  let(:path) { "test.html.erb" }
  let(:plugin_config) { {} }

  before do
    RuboCop::Herb::Configuration.setup(plugin_config)
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

  context "with a correction that would move HTML into ERB tags" do
    let(:source) do
      <<~ERB
        <% unless foo %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
        <%= x==1 %>
      ERB
    end
    let(:corrected) { source.sub("x==1", "x == 1") }

    it "corrects the other offenses only" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq corrected
    end

    it "reports the offense as not correctable" do
      runner.run(path, source, {})

      offenses = runner.offenses.map { [_1.cop_name, _1.correctable?] }
      expect(offenses).to eq [["Style/UnlessElse", false], ["Layout/SpaceAroundOperators", true]]
    end

    it "does not insert rubocop:todo comments with --disable-uncorrectable" do
      runner.run(path, source, { autocorrect: true, disable_uncorrectable: true })

      expect(runner.formatted_source).to eq corrected
    end

    context "with html_visualization enabled" do
      let(:plugin_config) { { "html_visualization" => true } }

      it "corrects the other offenses only" do
        runner.run(path, source, { autocorrect: true })

        expect(runner.formatted_source).to eq corrected
      end
    end
  end

  context "with a correction that would swap branches containing HTML" do
    let(:plugin_config) { { "html_visualization" => true } }
    let(:source) do
      <<~ERB
        <% if !foo %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
      ERB
    end

    it "keeps the template as is" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq source
    end
  end

  context "with a correction that would remove blank lines in HTML" do
    let(:source) { "<p>a</p>\n\n\n<p>b</p>\n" }

    it "keeps the template as is" do
      runner.run(path, source, { autocorrect: true })

      expect(runner.formatted_source).to eq source
    end
  end

  context "with a correction spanning multiple ERB tags that keeps HTML" do
    let(:source) do
      <<~ERB
        <% if a %>
          <p>x</p>
        <% else %>
          <% if b %>
            <p>y</p>
          <% end %>
        <% end %>
      ERB
    end
    let(:expected) do
      <<~ERB
        <% if a %>
          <p>x</p>
        <% elsif b %>
            <p>y</p>
        <% end %>
      ERB
    end

    it_behaves_like "an ERB autocorrector"
  end
end
