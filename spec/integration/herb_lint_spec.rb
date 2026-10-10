# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "yaml"

RSpec.describe "Lint with Herb/Lint cop", type: :feature do
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
  let(:rubocop_config) { RuboCop::Herb::Configuration.to_rubocop_config }
  let(:project_root) { File.expand_path("../fixtures/herb_lint", __dir__) }
  let(:path) { File.join(project_root, "app/views/test.html.erb") }

  before do
    RuboCop::Herb::Configuration.setup({})
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
    allow(RuboCop::ConfigFinder).to receive(:project_root).and_return(project_root)
  end

  after do
    config.unlink
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  def herb_lint_offenses
    runner.offenses.select { _1.cop_name == "Herb/Lint" }.map do |offense|
      [offense.severity.name, offense.line, offense.column, offense.location.source, offense.message]
    end
  end

  context "when the template has herb-lint offenses" do
    let(:source) do
      <<~ERB
        <div>
          <p>日本語<img src=logo.png></p>
          <%= @user.name %>
        </div>
      ERB
    end

    it "reports them as offenses of Herb/Lint" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq [
        [:warning, 2, 9, "img",
         "Herb/Lint: html-img-require-alt: Missing required `alt` attribute on `<img>` tag. " \
         "Add `alt=\"\"` for decorative images or `alt=\"description\"` for informative images."],
        [:error, 2, 17, "logo.png",
         "Herb/Lint: html-attribute-values-require-quotes: " \
         "Attribute value should be quoted: `src=\"logo.png\"`. Always wrap attribute values in quotes."]
      ]
    end
  end

  context "when the template has no herb-lint offenses" do
    let(:source) do
      <<~ERB
        <div>
          <img src="logo.png" alt="Logo">
          <%= @user.name %>
        </div>
      ERB
    end

    it "does not report any offenses" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq []
    end
  end

  context "when the herb-lint offense is disabled with herb:disable comment" do
    let(:source) do
      <<~ERB
        <img src="logo.png"> <%# herb:disable html-img-require-alt %>
      ERB
    end

    it "does not report the offense" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq []
    end
  end

  context "when the herb-lint offense is disabled with rubocop:disable comment" do
    let(:source) do
      <<~ERB
        <img src="logo.png"> <%# rubocop:disable Herb/Lint %>
      ERB
    end

    it "does not report the offense" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq []
    end
  end

  context "when herb-lint is not available" do
    let(:rubocop_config) do
      config = RuboCop::Herb::Configuration.to_rubocop_config
      config.merge("Herb/Lint" => config["Herb/Lint"].merge("NodeCommand" => node_command))
    end
    let(:source) { "<img src=\"logo.png\">\n" }
    let(:other_path) { File.join(project_root, "app/views/other.html.erb") }

    def startup_error(node_command)
      [:error, 1, 0, "<img src=\"logo.png\">",
       "Herb/Lint: herb-lint is not available: Node.js command not found: #{node_command}. " \
       "Set up herb-lint (`npm install --save-dev @herb-tools/linter`) or disable Herb/Lint cop."]
    end

    # Each context uses its own command name not to share the client (and its reported state) with others
    context "when multiple files are linted and the first file is linted again (e.g. rubocop --server or --lsp)" do
      let(:node_command) { "no-such-node-multiple-files" }

      it "reports the error only on the first file, including when it is linted again" do
        results = [path, other_path, path].map do |file|
          runner.run(file, source, {})
          herb_lint_offenses
        end
        expect(results).to eq [[startup_error(node_command)], [], [startup_error(node_command)]]
      end
    end

    context "when Herb/Lint is disabled at the first line of the first file" do
      let(:node_command) { "no-such-node-disabled" }

      it "reports the error on the next file" do
        results = [[path, "<%# rubocop:disable Herb/Lint %>\n#{source}"], [other_path, source]].map do |file, code|
          runner.run(file, code, {})
          herb_lint_offenses
        end
        expect(results).to eq [[], [startup_error(node_command)]]
      end
    end
  end
end
