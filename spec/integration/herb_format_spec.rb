# frozen_string_literal: true

require "spec_helper"

require "fileutils"
require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "tmpdir"
require "yaml"

RSpec.describe "Format with Herb/Formatting cop", type: :feature do
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
  let(:rubocop_config) do
    config = RuboCop::Herb::Configuration.to_rubocop_config
    config.merge(
      # Herb/Linting is tested in herb_lint_spec.rb
      "Herb/Linting" => config["Herb/Linting"].merge("Enabled" => herb_lint_enabled),
      "Herb/Formatting" => config["Herb/Formatting"].merge("NodeCommand" => node_command)
    )
  end
  let(:herb_lint_enabled) { false }
  let(:node_command) { "node" }
  let(:project_root) { File.expand_path("../fixtures/herb_format", __dir__) }
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

  def herb_format_offenses
    runner.offenses.select { _1.cop_name == "Herb/Formatting" }.map do |offense|
      [offense.severity.name, offense.line, offense.column, offense.location.source, offense.correctable?,
       offense.message]
    end
  end

  def offense(line, column, source)
    [:convention, line, column, source, true, "Herb/Formatting: Format the template as herb-format does."]
  end

  context "when the template is not formatted" do
    let(:source) do
      <<~ERB
        <div><p>日本語😀</p>
        <% if @user %>
        <span><%= @user.name %></span>
        <% end %>
        </div>
      ERB
    end

    context "when not autocorrecting" do
      it "reports each changed part as an offense" do
        runner.run(path, source, {})
        expect(herb_format_offenses).to eq [
          offense(1, 5, "<p>日本語😀</p>"),
          offense(2, 0, ""),
          offense(3, 0, ""),
          offense(4, 0, "")
        ]
      end
    end

    context "when autocorrecting with rubocop -A" do
      it "formats it" do
        runner.run(path, source, { autocorrect: true })
        expect(runner.formatted_source).to eq <<~ERB
          <div>
            <p>日本語😀</p>

            <% if @user %>
              <span><%= @user.name %></span>
            <% end %>
          </div>
        ERB
      end
    end

    # herb-format is in experimental preview, and changes the whitespace in HTML
    context "when autocorrecting with rubocop -a" do
      it "does not format it, as the autocorrection is unsafe" do
        runner.run(path, source, { autocorrect: true, safe_autocorrect: true })
        expect(runner.formatted_source).to eq source
      end
    end
  end

  context "when the template is formatted" do
    let(:source) do
      <<~ERB
        <div>
          <p><%= @user.name %></p>
        </div>
      ERB
    end

    it "does not report any offenses" do
      runner.run(path, source, {})
      expect(herb_format_offenses).to eq []
    end
  end

  # herb-format reindents the first line of a multi-line ERB tag only,
  # and Layout/ArgumentAlignment and Layout/HashAlignment realign the following lines
  context "when the template has a multi-line ERB tag" do
    let(:source) do
      <<~ERB
        <div>
        <%= render partial: "user",
                   locals: {
                     user: @user,
                     admin: true
                   } %>
        </div>
      ERB
    end

    it "formats it together with the corrections of the other cops" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq <<~ERB
        <div>
          <%= render partial: 'user',
                     locals: {
                       user: @user,
                       admin: true
                     } %>
        </div>
      ERB
    end
  end

  context "when Herb/Linting is enabled together" do
    let(:herb_lint_enabled) { true }
    let(:source) do
      <<~ERB
        <DIV class='user'><p><%= link_to("Home", root_path)  %></p></DIV>
      ERB
    end

    it "formats the template together with the fixes of herb-lint and the corrections of the other cops" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq <<~ERB
        <div class="user">
          <p><%= link_to('Home', root_path) %></p>
        </div>
      ERB
    end
  end

  context "when Herb/Formatting is disabled with rubocop:disable comment" do
    let(:source) do
      <<~ERB
        <%# rubocop:disable Herb/Formatting %>
        <div><p>a</p></div>
      ERB
    end

    it "does not format the template" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq source
    end
  end

  context "when the formatter is not enabled in .herb.yml" do
    # The command does not exist, so the cop reports an error if it spawns the server
    let(:node_command) { "no-such-node-formatter-disabled" }
    let(:source) { "<div><p>a</p></div>\n" }

    context "when the formatter is disabled" do
      let(:project_root) { File.expand_path("../fixtures/herb_format_disabled", __dir__) }

      it "does nothing without spawning herb-format" do
        runner.run(path, source, {})
        expect(herb_format_offenses).to eq []
      end
    end

    context "when .herb.yml has no formatter section" do
      let(:project_root) { Dir.mktmpdir }

      before { File.write(File.join(project_root, ".herb.yml"), "version: 0.11.0\nlinter:\n  enabled: true\n") }

      after { FileUtils.remove_entry(project_root) }

      it "does nothing without spawning herb-format" do
        runner.run(path, source, {})
        expect(herb_format_offenses).to eq []
      end
    end

    # Herb accepts anchors and aliases in .herb.yml
    context "when the formatter is disabled with an alias in .herb.yml" do
      let(:project_root) { Dir.mktmpdir }

      before do
        File.write(File.join(project_root, ".herb.yml"), <<~YAML)
          version: 0.11.0
          x-disabled: &disabled
            enabled: false
          formatter: *disabled
        YAML
      end

      after { FileUtils.remove_entry(project_root) }

      it "does nothing without spawning herb-format" do
        runner.run(path, source, {})
        expect(herb_format_offenses).to eq []
      end
    end

    context "when .herb.yml does not exist" do
      let(:project_root) { Dir.mktmpdir }

      after { FileUtils.remove_entry(project_root) }

      it "does nothing without spawning herb-format" do
        runner.run(path, source, {})
        expect(herb_format_offenses).to eq []
      end
    end
  end

  # e.g. a monorepo with .herb.yml and node_modules at its root, and a Rails application in a subdirectory
  context "when .herb.yml is in a parent directory of the project root" do
    let(:root) { Dir.mktmpdir }
    let(:project_root) { File.join(root, "web") }
    let(:source) { "<div>\n<p>a</p>\n</div>\n" }

    before do
      FileUtils.mkdir_p([project_root, File.join(root, ".herb/rewriters")])
      File.symlink(File.expand_path("../../node_modules", __dir__), File.join(root, "node_modules"))
      FileUtils.cp(File.expand_path("../fixtures/herb_format_rewriter/.herb/rewriters/prepend_comment.mjs", __dir__),
                   File.join(root, ".herb/rewriters"))
      File.write(File.join(root, ".herb.yml"), <<~YAML)
        version: 0.11.0
        formatter:
          enabled: true
          exclude:
            - "web/app/views/excluded/**/*"
          rewriter:
            post:
              - prepend-comment
      YAML
    end

    after { FileUtils.remove_entry(root) }

    it "formats the template with the rewriters in the directory of .herb.yml" do
      runner.run(path, source, { autocorrect: true })
      expect(runner.formatted_source).to eq "<%# formatted %>\n<div>\n  <p>a</p>\n</div>\n"
    end

    context "when the template is excluded by the patterns relative to the directory of .herb.yml" do
      let(:path) { File.join(project_root, "app/views/excluded/test.html.erb") }

      it "does not format it" do
        runner.run(path, source, { autocorrect: true })
        expect(runner.formatted_source).to eq source
      end
    end
  end

  context "when .herb.yml is invalid" do
    let(:project_root) { Dir.mktmpdir }
    # The command does not exist, so the cop reports an error when it spawns the server
    let(:node_command) { "no-such-node-invalid-config" }
    let(:source) { "<div></div>\n" }

    before { File.write(File.join(project_root, ".herb.yml"), "formatter: [\n") }

    after { FileUtils.remove_entry(project_root) }

    it "spawns herb-format to report the error" do
      runner.run(path, source, {})
      expect(herb_format_offenses.map(&:last)).to eq [
        "Herb/Formatting: herb-format is not available: Node.js command not found: #{node_command}. " \
        "Set up herb-format (`npm install --save-dev @herb-tools/formatter`) or disable Herb/Formatting cop."
      ]
    end
  end

  context "when herb-format is not available" do
    let(:source) { "<div></div>\n" }
    let(:other_path) { File.join(project_root, "app/views/other.html.erb") }

    def startup_error(node_command)
      [:error, 1, 0, "<div></div>", false,
       "Herb/Formatting: herb-format is not available: Node.js command not found: #{node_command}. " \
       "Set up herb-format (`npm install --save-dev @herb-tools/formatter`) or disable Herb/Formatting cop."]
    end

    # Each context uses its own command name not to share the client (and its reported state) with others
    context "when multiple files are formatted" do
      let(:node_command) { "no-such-node-formatter-multiple-files" }

      it "reports the error only on the first file, including when it is formatted again" do
        results = [path, other_path, path].map do |file|
          runner.run(file, source, {})
          herb_format_offenses
        end
        expect(results).to eq [[startup_error(node_command)], [], [startup_error(node_command)]]
      end
    end
  end
end
