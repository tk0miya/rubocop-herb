# frozen_string_literal: true

require "spec_helper"

require "fileutils"
require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "tmpdir"
require "yaml"

RSpec.describe "Lint with Herb/Linting cop", type: :feature do
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
    runner.offenses.select { _1.cop_name == "Herb/Linting" }.map do |offense|
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

    it "reports them as offenses of Herb/Linting" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq [
        [:warning, 2, 9, "img",
         "Herb/Linting: [html-img-require-alt] Missing required `alt` attribute on `<img>` tag. " \
         "Add `alt=\"\"` for decorative images or `alt=\"description\"` for informative images."],
        [:error, 2, 17, "logo.png",
         "Herb/Linting: [html-attribute-values-require-quotes] " \
         "Attribute value should be quoted: `src=\"logo.png\"`. Always wrap attribute values in quotes."]
      ]
    end
  end

  context "when the severities of herb-lint offenses are info and hint" do
    let(:project_root) { File.expand_path("../fixtures/herb_lint_severity", __dir__) }
    let(:source) { "<img src=logo.png>\n" }

    it "reports them as convention and refactor" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq [
        [:convention, 1, 1, "img",
         "Herb/Linting: [html-img-require-alt] Missing required `alt` attribute on `<img>` tag. " \
         "Add `alt=\"\"` for decorative images or `alt=\"description\"` for informative images."],
        [:refactor, 1, 9, "logo.png",
         "Herb/Linting: [html-attribute-values-require-quotes] " \
         "Attribute value should be quoted: `src=\"logo.png\"`. Always wrap attribute values in quotes."]
      ]
    end
  end

  # e.g. a monorepo with .herb.yml and node_modules at its root, and a Rails application in a subdirectory
  context "when .herb.yml is in a parent directory of the project root" do
    let(:root) { Dir.mktmpdir }
    let(:project_root) { File.join(root, "web") }
    let(:source) { "<img src=\"logo.png\">\n" }

    before do
      FileUtils.mkdir_p([project_root, File.join(root, ".herb/rules")])
      File.symlink(File.expand_path("../../node_modules", __dir__), File.join(root, "node_modules"))
      FileUtils.cp(File.expand_path("../fixtures/herb_lint_noisy/.herb/rules/noisy.mjs", __dir__),
                   File.join(root, ".herb/rules"))
      File.write(File.join(root, ".herb.yml"), <<~YAML)
        version: 0.11.0
        framework: actionview
        linter:
          exclude:
            - "web/app/views/excluded/**/*"
      YAML
    end

    after { FileUtils.remove_entry(root) }

    it "lints the template with the custom rules in the directory of .herb.yml" do
      expect { runner.run(path, source, {}) }
        .to output("noisy output from a custom rule\n").to_stderr_from_any_process
      expect(herb_lint_offenses.map(&:last)).to eq [
        "Herb/Linting: [html-img-require-alt] Missing required `alt` attribute on `<img>` tag. " \
        "Add `alt=\"\"` for decorative images or `alt=\"description\"` for informative images."
      ]
    end

    context "when the template is excluded by the patterns relative to the directory of .herb.yml" do
      let(:path) { File.join(project_root, "app/views/excluded/test.html.erb") }

      it "does not lint it" do
        runner.run(path, source, {})
        expect(herb_lint_offenses).to eq []
      end
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

  context "when the template has an empty ERB tag" do
    let(:source) do
      <<~ERB
        <div>
          <% %>
        </div>
      ERB
    end

    it "reports it as an offense of Herb/EmptyErbTag only" do
      runner.run(path, source, {})
      expect(runner.offenses.map(&:cop_name)).to eq ["Herb/EmptyErbTag"]
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
        <img src="logo.png"> <%# rubocop:disable Herb/Linting %>
      ERB
    end

    it "does not report the offense" do
      runner.run(path, source, {})
      expect(herb_lint_offenses).to eq []
    end
  end

  context "when the template has autocorrectable herb-lint offenses" do
    let(:source) do
      <<~ERB
        <DIV class='user'>
          <p>日本語😀<IMG src="logo.png" alt="Logo"></p>
        </DIV>
      ERB
    end

    context "when not autocorrecting" do
      it "reports them as correctable" do
        runner.run(path, source, {})
        offenses = runner.offenses.select { _1.cop_name == "Herb/Linting" }
        expect(offenses.map { [_1.line, _1.column, _1.correctable?] })
          .to eq [[1, 1, true], [1, 11, true], [2, 10, true], [3, 2, true]]
      end
    end

    # The fixes of the opening and closing tags of DIV and the attribute in it overlap,
    # so they are applied over the iterations of autocorrection
    context "when autocorrecting with rubocop -a" do
      it "autocorrects them" do
        runner.run(path, source, { autocorrect: true, safe_autocorrect: true })
        expect(runner.formatted_source).to eq <<~ERB
          <div class="user">
            <p>日本語😀<img src="logo.png" alt="Logo"></p>
          </div>
        ERB
      end
    end
  end

  context "when the template has herb-lint offenses autocorrected along with the Ruby code" do
    let(:source) do
      <<~ERB
        <p><%= link_to("Home", root_path)  %></p>
      ERB
    end

    it "autocorrects both of them" do
      runner.run(path, source, { autocorrect: true, safe_autocorrect: true })
      expect(runner.formatted_source).to eq <<~ERB
        <p><%= link_to('Home', root_path) %></p>
      ERB
    end
  end

  # Style/CombinableLoops removes `end` and inserts ` end` after it, which turns `<% end %>` into `<%  end %>`
  context "when a correction of another cop leaves extra whitespace in an ERB tag" do
    let(:source) do
      <<~ERB
        <% items.each do |item| %>
          <%= item %>
        <% end %>
        <% items.each do |item| %>
          <%= item.name %>
        <% end %>
      ERB
    end

    context "when autocorrecting with rubocop -A" do
      it "removes the whitespace with the fix of herb-lint (erb-no-extra-whitespace-inside-tags)" do
        runner.run(path, source, { autocorrect: true })
        expect(runner.formatted_source).to eq <<~ERB
          <% items.each do |item| %>
            <%= item %>
            <%= item.name %>
          <% end %>
        ERB
      end
    end
  end

  context "when the template has herb-lint offenses autocorrectable only unsafely" do
    let(:source) { "<p>Tom & Jerry</p>\n" }

    context "when not autocorrecting" do
      it "reports them as correctable" do
        runner.run(path, source, {})
        expect(runner.offenses.map { [_1.cop_name, _1.correctable?] }).to eq [["Herb/Linting", true]]
      end
    end

    context "when autocorrecting with rubocop -a" do
      it "does not autocorrect them and reports them as not correctable" do
        runner.run(path, source, { autocorrect: true, safe_autocorrect: true })
        expect(runner.formatted_source).to eq source
        expect(runner.offenses.map { [_1.cop_name, _1.correctable?] }).to eq [["Herb/Linting", false]]
      end
    end

    context "when autocorrecting with rubocop -A" do
      it "autocorrects them" do
        runner.run(path, source, { autocorrect: true })
        expect(runner.formatted_source).to eq "<p>Tom &amp; Jerry</p>\n"
      end
    end
  end

  context "when the autocorrectable herb-lint offense is disabled with rubocop:disable comment" do
    let(:source) do
      <<~ERB
        <IMG src="logo.png" alt="Logo"> <%# rubocop:disable Herb/Linting %>
      ERB
    end

    it "does not autocorrect it" do
      runner.run(path, source, { autocorrect: true, safe_autocorrect: true })
      expect(runner.formatted_source).to eq source
    end
  end

  context "when herb-lint is not available" do
    let(:rubocop_config) do
      config = RuboCop::Herb::Configuration.to_rubocop_config
      config.merge("Herb/Linting" => config["Herb/Linting"].merge("NodeCommand" => node_command))
    end
    let(:source) { "<img src=\"logo.png\">\n" }
    let(:other_path) { File.join(project_root, "app/views/other.html.erb") }

    def startup_error(node_command)
      [:error, 1, 0, "<img src=\"logo.png\">",
       "Herb/Linting: herb-lint is not available: Node.js command not found: #{node_command}. " \
       "Set up herb-lint (`npm install --save-dev @herb-tools/linter`) or disable Herb/Linting cop."]
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

    context "when Herb/Linting is disabled at the first line of the first file" do
      let(:node_command) { "no-such-node-disabled" }

      it "reports the error on the next file" do
        results = [[path, "<%# rubocop:disable Herb/Linting %>\n#{source}"], [other_path, source]].map do |file, code|
          runner.run(file, code, {})
          herb_lint_offenses
        end
        expect(results).to eq [[], [startup_error(node_command)]]
      end
    end

    context "when the template is empty" do
      let(:node_command) { "no-such-node-empty-file" }

      # Formatters fail to read the source line of an offense at a range in an empty file
      it "reports the error to the whole file" do
        runner.run(path, "", {})
        offenses = runner.offenses.map { [_1.cop_name, _1.location, _1.message] }
        expect(offenses).to eq [
          ["Herb/Linting", RuboCop::Cop::Offense::NO_LOCATION, startup_error(node_command).last],
          ["Lint/EmptyFile", RuboCop::Cop::Offense::NO_LOCATION, "Lint/EmptyFile: Empty file detected."]
        ]
      end
    end
  end
end
