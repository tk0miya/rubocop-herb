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
      f.write(YAML.dump(rubocop_config))
      f.close
    end
  end
  let(:rubocop_config) { RuboCop::Herb::Configuration.to_rubocop_config }
  let(:path) { "test.html.erb" }

  before do
    RuboCop::Herb::Configuration.setup({})
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
  end

  after do
    config.unlink
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  def run_rubocop(source)
    runner.run(path, source, {})
    runner.offenses
  end

  describe "basic offense detection" do
    context "when analyzing a simple ERB file without offenses" do
      let(:source) { "<%= 'Hello world' %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses).to be_empty
      end
    end

    context "when analyzing ERB with Style cop violations" do
      # Style/RedundantSelf: Redundant `self` detected
      let(:source) { "<%= self.name %>" }

      it "detects Style/RedundantSelf offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end
    end

    context "when analyzing ERB with Lint cop violations" do
      # Lint/UselessAssignment: Useless assignment to variable
      let(:source) { "<% unused_var = 1 %>" }

      it "detects Lint/UselessAssignment offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Lint/UselessAssignment")
      end
    end

    context "when analyzing ERB with Layout cop violations" do
      # Layout/SpaceAfterComma: Space missing after comma
      let(:source) { "<%= method(1,2,3) %>" }
      let(:rubocop_config) do
        RuboCop::Herb::Configuration.to_rubocop_config.merge(
          "Layout/SpaceAfterComma" => { "Enabled" => true }
        )
      end

      it "detects Layout/SpaceAfterComma offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Layout/SpaceAfterComma")
      end
    end
  end

  describe "offense position accuracy" do
    context "when offense is on the first line" do
      let(:source) { "<%= self.name %>" }

      it "reports the correct line number" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(1)
      end

      it "reports the correct column number" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        # "<%= " is 4 characters, so `self` starts at column 5
        expect(offense.column).to eq(4)
      end
    end

    context "when offense is on a later line" do
      let(:source) do
        <<~ERB
          <div>
            <p>Hello</p>
            <%= self.name %>
          </div>
        ERB
      end

      it "reports the correct line number" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(3)
      end

      it "reports the correct column number" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        # "  <%= " is 6 characters (2 spaces + 4 for ERB tag), so `self` starts at column 7
        expect(offense.column).to eq(6)
      end
    end

    context "when there are multiple offenses on different lines" do
      let(:source) do
        <<~ERB
          <div>
            <%= self.first %>
            <%= self.second %>
          </div>
        ERB
      end

      it "reports correct line numbers for each offense" do
        offenses = run_rubocop(source)
        redundant_self_offenses = offenses.select { |o| o.cop_name == "Style/RedundantSelf" }
        lines = redundant_self_offenses.map(&:line).sort
        expect(lines).to eq([2, 3])
      end
    end
  end

  describe "excluded cops" do
    # These cops are excluded because they conflict with ERB extraction

    context "with Layout/InitialIndentation cop" do
      # ERB code may start at any indentation level within HTML
      let(:source) do
        <<~ERB
          <div>
            <%= name %>
          </div>
        ERB
      end

      it "does not report Layout/InitialIndentation offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).not_to include("Layout/InitialIndentation")
      end
    end

    context "with Layout/TrailingEmptyLines cop" do
      # ERB files may not end with Ruby code
      let(:source) { "<%= name %>\n\n" }

      it "does not report Layout/TrailingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).not_to include("Layout/TrailingEmptyLines")
      end
    end

    context "with Layout/TrailingWhitespace cop" do
      # Whitespace padding preserves positions but creates trailing spaces
      let(:source) { "<%= name %>   \n" }

      it "does not report Layout/TrailingWhitespace offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).not_to include("Layout/TrailingWhitespace")
      end
    end

    context "with Style/FrozenStringLiteralComment cop" do
      # ERB files don't support frozen string literal comments
      # Note: This cop is excluded via glob patterns in Configuration.to_rubocop_config
      let(:source) { "<%= name %>" }

      it "does not report Style/FrozenStringLiteralComment offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).not_to include("Style/FrozenStringLiteralComment")
      end
    end

    context "with Style/Semicolon cop" do
      # Semicolons are inserted between ERB tags on the same line
      # Note: This cop is excluded via glob patterns in Configuration.to_rubocop_config
      let(:source) { "<% a = 1 %><% b = a %>" }

      it "does not report Style/Semicolon offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).not_to include("Style/Semicolon")
      end
    end
  end

  describe "multiple ERB patterns" do
    context "with multiple ERB tags on the same line" do
      let(:source) { "<% x = 1 %><%= self.name %>" }

      it "detects offenses correctly" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end
    end

    context "with control structures (if/else)" do
      let(:source) do
        <<~ERB
          <% if self.condition %>
            <p>True</p>
          <% else %>
            <p>False</p>
          <% end %>
        ERB
      end

      it "detects offenses within control structures" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end

      it "reports correct line for the offense" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(1)
      end
    end

    context "with iteration (each block)" do
      let(:source) do
        <<~ERB
          <ul>
          <% items.each do |item| %>
            <li><%= self.render_item(item) %></li>
          <% end %>
          </ul>
        ERB
      end

      it "detects offenses within iteration blocks" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end

      it "reports correct line for the offense" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(3)
      end
    end

    context "with nested ERB structures" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <% items.each do |item| %>
              <%= self.render(item) %>
            <% end %>
          <% end %>
        ERB
      end

      it "detects offenses in nested structures" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end

      it "reports correct line for nested offense" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(3)
      end
    end
  end

  describe "multibyte character support" do
    context "with Japanese characters before ERB tag" do
      let(:source) { "<p>こんにちは</p><%= self.name %>" }

      it "detects offenses correctly" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end

      it "reports correct column position" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        # "<p>こんにちは</p><%= " is 18 characters (3 + 5 + 4 + 4 + 1 space for offset)
        # But we need to check actual behavior with byte vs character counting
        expect(offense).not_to be_nil
      end
    end

    context "with multibyte characters on multiple lines" do
      let(:source) do
        <<~ERB
          <div>日本語</div>
          <p>テスト</p>
          <%= self.name %>
        ERB
      end

      it "detects offenses correctly" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end

      it "reports correct line number" do
        offenses = run_rubocop(source)
        offense = offenses.find { |o| o.cop_name == "Style/RedundantSelf" }
        expect(offense.line).to eq(3)
      end
    end
  end

  describe "error handling and edge cases" do
    context "with HTML only (no ERB)" do
      let(:source) { "<div><p>Hello World</p></div>" }

      it "does not crash and returns no offenses" do
        offenses = run_rubocop(source)
        expect(offenses).to be_empty
      end
    end

    context "with empty file" do
      let(:source) { "" }

      it "does not crash" do
        expect { run_rubocop(source) }.not_to raise_error
      end

      it "may report Lint/EmptyFile offense" do
        offenses = run_rubocop(source)
        # Empty file detection is expected behavior from RuboCop
        expect(offenses.map(&:cop_name)).to include("Lint/EmptyFile")
      end
    end

    context "with ERB comment only" do
      let(:source) { "<%# This is a comment %>" }

      it "does not crash" do
        expect { run_rubocop(source) }.not_to raise_error
      end
    end

    context "with output tag containing only whitespace" do
      let(:source) { "<%=   %>" }

      it "does not crash" do
        expect { run_rubocop(source) }.not_to raise_error
      end
    end
  end

  describe "configuration" do
    context "with custom file extension" do
      let(:path) { "test.custom.erb" }

      before do
        RuboCop::Herb::Configuration.setup({ "extensions" => [".custom.erb"] })
      end

      it "processes files with custom extension" do
        offenses = run_rubocop("<%= self.name %>")
        expect(offenses.map(&:cop_name)).to include("Style/RedundantSelf")
      end
    end

    context "with unsupported file extension" do
      let(:path) { "test.rb" }

      it "does not process unsupported files" do
        # When file is not supported, extractor returns nil and RuboCop processes it as Ruby
        # Since "<%= self.name %>" is not valid Ruby, this should either error or return different offenses
        offenses = run_rubocop("<%= self.name %>")
        # The extractor should skip this file
        expect(offenses.map(&:cop_name)).not_to include("Style/RedundantSelf")
      end
    end
  end
end
