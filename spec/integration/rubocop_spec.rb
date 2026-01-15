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

  describe "offense position accuracy" do
    context "when ERB extraction causes Layout/LeadingEmptyLines" do
      let(:source) do
        <<~ERB
          <div>
            <p>Hello</p>
            <%= user.name %>
          </div>
        ERB
      end

      it "detects Layout/LeadingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Layout/LeadingEmptyLines"])
      end

      it "reports the correct line number for extracted Ruby" do
        offenses = run_rubocop(source)
        # Line 3 is where the Ruby code appears in the extracted source
        expect(offenses.first.line).to eq(3)
      end
    end

    context "with multiple ERB tags on different lines" do
      let(:source) do
        <<~ERB
          <div>
            <%= first_value %>
            <%= second_value %>
          </div>
        ERB
      end

      it "detects Layout/LeadingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Layout/LeadingEmptyLines"])
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
            <%= user.name %>
          </div>
        ERB
      end

      it "does not report Layout/InitialIndentation offense" do
        offenses = run_rubocop(source)
        # Layout/LeadingEmptyLines is detected due to ERB extraction adding empty lines
        expect(offenses.map(&:cop_name)).to eq(["Layout/LeadingEmptyLines"])
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
        # Layout/ExtraSpacing may be detected due to ERB tag spacing
        expect(offenses.map(&:cop_name)).to eq(["Layout/ExtraSpacing"])
      end
    end
  end

  describe "ERB extraction side effects" do
    context "with multiple ERB tags on the same line" do
      let(:source) { "<% x = 1 %><% puts x %><%= value %>" }

      it "detects Layout/ExtraSpacing from ERB tag boundaries" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/ExtraSpacing", "Layout/ExtraSpacing"]
        )
      end
    end

    context "with control structures (if/else)" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <p>True</p>
          <% else %>
            <p>False</p>
          <% end %>
        ERB
      end

      it "detects offenses from ERB extraction" do
        offenses = run_rubocop(source)
        # ERB extraction creates patterns that trigger these cops
        expect(offenses.map(&:cop_name)).to eq(
          ["Lint/EmptyConditionalBody", "Style/IfWithSemicolon", "Style/EmptyElse"]
        )
      end
    end

    context "with iteration (each block)" do
      let(:source) do
        <<~ERB
          <ul>
          <% items.each do |item| %>
            <li><%= format_item(item) %></li>
          <% end %>
          </ul>
        ERB
      end

      it "detects offenses from ERB extraction" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/LeadingEmptyLines", "Layout/IndentationWidth"]
        )
      end
    end

    context "with nested ERB structures" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <% items.each do |item| %>
              <%= render_item(item) %>
            <% end %>
          <% end %>
        ERB
      end

      it "detects offenses from ERB extraction" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(
          ["Style/IfWithSemicolon", "Layout/IndentationWidth"]
        )
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

    context "with block using do...end on same line" do
      let(:source) { "<% items.each do |item| %><%= item %><% end %>" }

      it "detects offenses from ERB extraction" do
        offenses = run_rubocop(source)
        # do...end block joined with semicolons triggers multiple cops
        expect(offenses.map(&:cop_name)).to eq(
          ["Style/BlockDelimiters", "Layout/ExtraSpacing", "Lint/Void", "Layout/ExtraSpacing"]
        )
      end
    end

    context "with lambda expression" do
      let(:source) { "<% fn = ->(x) { x * 2 } %><%= fn.call(5) %>" }

      it "detects Layout/ExtraSpacing from tag boundaries" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Layout/ExtraSpacing"])
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

    context "with case/when structure" do
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

      it "detects Lint/EmptyWhen due to HTML between when clauses" do
        offenses = run_rubocop(source)
        # HTML content between case/when creates empty when bodies
        expect(offenses.map(&:cop_name)).to eq(["Lint/EmptyWhen", "Lint/EmptyWhen"])
      end
    end

    context "with unless modifier" do
      let(:source) do
        <<~ERB
          <% unless hidden %>
            <div>Content</div>
          <% end %>
        ERB
      end

      it "detects offenses from ERB extraction" do
        offenses = run_rubocop(source)
        # HTML content creates empty conditional body
        expect(offenses.map(&:cop_name)).to eq(
          ["Lint/EmptyConditionalBody", "Style/IfWithSemicolon"]
        )
      end
    end

    context "with while loop" do
      let(:source) do
        <<~ERB
          <% while i < 10 %>
            <%= i %>
            <% i += 1 %>
          <% end %>
        ERB
      end

      it "detects indentation offenses" do
        offenses = run_rubocop(source)
        # Multiline ERB extraction causes indentation issues
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/IndentationWidth", "Layout/IndentationConsistency"]
        )
      end
    end

    context "with for loop" do
      let(:source) do
        <<~ERB
          <% for item in items %>
            <%= item %>
          <% end %>
        ERB
      end

      it "detects Style/For and indentation offenses" do
        offenses = run_rubocop(source)
        # Style/For suggests using each instead
        expect(offenses.map(&:cop_name)).to eq(["Style/For", "Layout/IndentationWidth"])
      end
    end

    context "with begin/rescue/ensure" do
      let(:source) do
        <<~ERB
          <% begin %>
            <%= risky_operation %>
          <% rescue StandardError => e %>
            <%= e.message %>
          <% ensure %>
            <%= cleanup %>
          <% end %>
        ERB
      end

      it "detects indentation offenses" do
        offenses = run_rubocop(source)
        # Multiline begin/rescue/ensure extraction causes indentation issues
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/IndentationWidth", "Layout/IndentationWidth", "Layout/IndentationWidth"]
        )
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

    context "with next in block" do
      let(:source) do
        <<~ERB
          <% items.each do |i| %>
            <% next if i.nil? %>
            <%= i %>
          <% end %>
        ERB
      end

      it "detects offenses from do...end block extraction" do
        offenses = run_rubocop(source)
        # Guard clause and indentation issues from multiline extraction
        expect(offenses.map(&:cop_name)).to eq(
          ["Layout/EmptyLineAfterGuardClause", "Layout/IndentationConsistency", "Lint/Void"]
        )
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

      it "detects Layout/LeadingEmptyLines offense" do
        offenses = run_rubocop(source)
        expect(offenses.map(&:cop_name)).to eq(["Layout/LeadingEmptyLines"])
      end

      it "reports correct line number for extracted Ruby" do
        offenses = run_rubocop(source)
        # Line 3 is where the Ruby code appears in the extracted source
        expect(offenses.first.line).to eq(3)
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

      it "reports Layout/CommentIndentation offense" do
        offenses = run_rubocop(source)
        # Comment is extracted and triggers indentation check
        expect(offenses.map(&:cop_name)).to eq(["Layout/CommentIndentation"])
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
