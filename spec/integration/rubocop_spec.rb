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

  describe "basic functionality" do
    context "with simple output tag" do
      let(:source) { "<%= user.name %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with simple execution tag" do
      let(:source) { "<% puts message %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with string literal" do
      let(:source) { "<%= 'Hello world' %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end
  end

  describe "excluded cops" do
    # These cops are excluded due to inherent incompatibilities with ERB extraction
    # Verify that they are properly excluded from analysis

    context "with Layout/LeadingEmptyLines cop" do
      # ERB files may not start with Ruby code
      let(:source) do
        <<~ERB
          <div>
            <p>Hello</p>
            <%= user.name %>
          </div>
        ERB
      end

      it "does not report Layout/LeadingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/InitialIndentation cop" do
      # ERB code may start at any indentation level within HTML
      let(:source) do
        <<~ERB
          <div>
            <%= user.name %>
          </div>
        ERB
      end

      it "does not report Layout/InitialIndentation offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/TrailingEmptyLines cop" do
      # ERB files may not end with Ruby code
      let(:source) { "<%= user.name %>\n\n" }

      it "does not report Layout/TrailingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/TrailingWhitespace cop" do
      # Whitespace padding preserves positions but creates trailing spaces
      let(:source) { "<%= user.name %>   \n" }

      it "does not report Layout/TrailingWhitespace offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Style/FrozenStringLiteralComment cop" do
      # ERB files don't support frozen string literal comments
      let(:source) { "<%= user.name %>" }

      it "does not report Style/FrozenStringLiteralComment offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Style/Semicolon cop" do
      # Semicolons are inserted between ERB tags on the same line
      let(:source) { "<% puts 1 %><% puts 2 %>" }

      it "does not report Style/Semicolon offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Style/IfWithSemicolon cop" do
      # Semicolons are inserted between ERB tags on the same line
      let(:source) do
        <<~ERB
          <% if condition %>
            <p>Content</p>
          <% end %>
        ERB
      end

      it "does not report Style/IfWithSemicolon offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/ExtraSpacing cop" do
      # Whitespace padding preserves positions but creates extra spaces
      let(:source) { "<% x = 1 %><% puts x %><%= value %>" }

      it "does not report Layout/ExtraSpacing offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/IndentationWidth cop" do
      # Ruby code in ERB may have different indentation width
      let(:source) do
        <<~ERB
          <ul>
          <% items.each do |item| %>
            <li><%= format_item(item) %></li>
          <% end %>
          </ul>
        ERB
      end

      it "does not report Layout/IndentationWidth offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Layout/CommentIndentation cop" do
      # ERB comment to Ruby comment conversion shifts column position
      let(:source) { "<%# This is a comment %>" }

      it "does not report Layout/CommentIndentation offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end
  end

  describe "HTML-related excluded cops" do
    # These cops are temporarily excluded because HTML parts are replaced with whitespace

    context "with Lint/EmptyConditionalBody cop" do
      # Conditional bodies may contain only HTML (no Ruby code)
      let(:source) do
        <<~ERB
          <% if condition %>
            <p>True</p>
          <% else %>
            <p>False</p>
          <% end %>
        ERB
      end

      it "does not report Lint/EmptyConditionalBody offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Lint/EmptyWhen cop" do
      # When bodies may contain only HTML (no Ruby code)
      let(:source) do
        <<~ERB
          <% case status %>
          <% when :pending %>
            <span>Pending</span>
          <% when :done %>
            <span>Done</span>
          <% end %>
        ERB
      end

      it "does not report Lint/EmptyWhen offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with Style/EmptyElse cop" do
      # Else branches may contain only HTML (no Ruby code)
      let(:source) do
        <<~ERB
          <% if condition %>
            <%= value %>
          <% else %>
            <p>No value</p>
          <% end %>
        ERB
      end

      it "does not report Style/EmptyElse offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end
  end

  describe "user code offenses" do
    # Verify that actual user code issues are still detected

    context "with Style/For cop" do
      let(:source) do
        <<~ERB
          <% for item in items %>
            <%= item %>
          <% end %>
        ERB
      end

      it "detects Style/For offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Style/For"])
      end
    end

    context "with Style/BlockDelimiters cop" do
      let(:source) { "<% items.each do |item| %><%= item %><% end %>" }

      it "detects Style/BlockDelimiters offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Style/BlockDelimiters", "Lint/Void"])
      end
    end

    context "with Layout/EmptyLineAfterGuardClause cop" do
      let(:source) do
        <<~ERB
          <% items.each do |i| %>
            <% next if i.nil? %>
            <%= i %>
          <% end %>
        ERB
      end

      it "detects Layout/EmptyLineAfterGuardClause offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/EmptyLineAfterGuardClause", "Layout/IndentationConsistency", "Lint/Void"]
        )
      end
    end

    context "with Lint/Void cop" do
      let(:source) { "<% items.each do |item| %><%= item %><% end %>" }

      it "detects Lint/Void offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to include("Lint/Void")
      end
    end
  end

  describe "Ruby syntax patterns" do
    context "with block using braces" do
      let(:source) { "<%= items.map(&:to_s) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with lambda expression" do
      let(:source) { "<% fn = ->(x) { x * 2 } %><%= fn.call(5) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with safe navigation operator" do
      let(:source) { "<%= user&.name %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with splat operator" do
      let(:source) { "<%= method_call(*args) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with double splat operator" do
      let(:source) { "<%= method_call(**options) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with yield" do
      let(:source) { "<%= yield %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with yield and content_for" do
      let(:source) { "<%= yield :sidebar %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with early return" do
      let(:source) { "<% return if condition %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with instance variable" do
      let(:source) { "<%= @user.name %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with ternary operator" do
      let(:source) { "<%= admin ? admin_link : user_link %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with string interpolation" do
      let(:source) { '<%= "Hello #{username}" %>' }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with array literal" do
      let(:source) { "<%= [1, 2, 3].sum %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with hash literal" do
      let(:source) { "<%= { key: value }[:key] %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with range" do
      let(:source) { "<%= (1..10).to_a %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with regex" do
      let(:source) { "<%= text.match(/pattern/) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with constant reference" do
      let(:source) { "<%= MyClass::CONSTANT %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with logical operators" do
      let(:source) { "<%= a && b || c %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with method chain" do
      let(:source) { "<%= items.map(&:to_s).compact.join %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with defined? operator" do
      let(:source) { "<%= defined?(variable) %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end
  end

  describe "multibyte character support" do
    context "with Japanese characters before ERB tag" do
      let(:source) { "<p>こんにちは</p><%= user.name %>" }

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with multibyte characters on multiple lines" do
      let(:source) do
        <<~ERB
          <div>日本語</div>
          <p>テスト</p>
          <%= user.name %>
        ERB
      end

      it "detects no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end
  end

  describe "error handling and edge cases" do
    context "with HTML only (no ERB)" do
      let(:source) { "<div><p>Hello World</p></div>" }

      it "returns no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with empty file" do
      let(:source) { "" }

      it "reports Lint/EmptyFile offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Lint/EmptyFile"])
      end
    end

    context "with ERB comment only" do
      let(:source) { "<%# This is a comment %>" }

      it "does not report Layout/CommentIndentation offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with output tag containing only whitespace" do
      let(:source) { "<%=   %>" }

      it "returns no offenses" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq([])
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
        offenses = run_rubocop("<%= user.name %>")
        expect(offenses.map(&:cop_name)).to eq([])
      end
    end

    context "with unsupported file extension" do
      let(:path) { "test.rb" }

      it "does not process as ERB and reports syntax error" do
        # When file is not supported, extractor returns nil and RuboCop processes it as Ruby
        # Since "<%= user.name %>" is not valid Ruby, it reports a syntax error
        offenses = run_rubocop("<%= user.name %>")
        expect(offenses.map(&:cop_name)).to eq(["Lint/Syntax"])
      end
    end
  end
end
