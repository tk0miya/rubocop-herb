# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "yaml"

RSpec.describe "Autocorrect with RuboCop", type: :feature do
  context "with a single cop", :config do
    include_context "with ERB source"

    # Each context picks an existing cop only as an example of the correction it describes
    context "when a correction stays inside an ERB tag" do
      let(:cop_class) { RuboCop::Cop::Layout::SpaceAroundOperators }

      it "corrects the offense" do
        expect_offense(<<~ERB)
          <div><%= x==1 %></div>
                    ^^ Surrounding space missing for operator `==`.
        ERB

        expect_correction(<<~ERB)
          <div><%= x == 1 %></div>
        ERB
      end
    end

    context "when a correction replaces an expression inside an ERB tag" do
      let(:cop_class) { RuboCop::Cop::Style::StringConcatenation }

      it "corrects the offense" do
        expect_offense(<<~ERB)
          <p><%= 'Hello' + 'World' %></p>
                 ^^^^^^^^^^^^^^^^^ Prefer string interpolation to string concatenation.
        ERB

        expect_correction(<<~ERB)
          <p><%= "HelloWorld" %></p>
        ERB
      end
    end

    context "when a correction rewrites a method call inside an ERB tag" do
      let(:cop_class) { RuboCop::Cop::Style::ZeroLengthPredicate }

      it "corrects the offense" do
        expect_offense(<<~ERB)
          <%= arr.length == 0 %>
              ^^^^^^^^^^^^^^^ Use `empty?` instead of `length == 0`.
        ERB

        expect_correction(<<~ERB)
          <%= arr.empty? %>
        ERB
      end
    end

    context "when a correction spans multiple lines inside an ERB tag" do
      let(:cop_class) { RuboCop::Cop::Layout::HashAlignment }

      it "corrects the offense" do
        expect_offense(<<~ERB)
          <%= render locals: {
            foo: 1,
            barbaz:   2
            ^^^^^^^^^^^ Align the keys of a hash literal if they span more than one line.
          } %>
        ERB

        expect_correction(<<~ERB)
          <%= render locals: {
            foo: 1,
            barbaz: 2
          } %>
        ERB
      end
    end

    context "when a correction removes an ERB tag and keeps HTML" do
      let(:cop_class) { RuboCop::Cop::Style::EmptyElse }

      it "corrects the offense" do
        expect_offense(<<~ERB)
          <% if a %>
            <p>x</p>
          <% else %>
             ^^^^ Redundant `else`-clause.
          <% end %>
        ERB

        expect_correction(<<~ERB)
          <% if a %>
            <p>x</p>
          <% end %>
        ERB
      end
    end

    context "when a correction would swap branches containing HTML" do
      let(:cop_class) { RuboCop::Cop::Style::UnlessElse }

      it "reports the offense as not correctable" do
        offenses = expect_offense(<<~ERB)
          <% unless foo %>
             ^^^^^^^^^^^^^ Do not use `unless` with `else`. Rewrite these with the positive case first.
            <p>a</p>
          <% else %>
            <p>b</p>
          <% end %>
        ERB

        expect(offenses.map(&:correctable?)).to eq [false]
        expect_no_corrections
      end
    end

    context "when a correction would invert a condition of branches containing HTML" do
      let(:cop_class) { RuboCop::Cop::Style::NegatedIfElseCondition }

      it "reports the offense as not correctable" do
        offenses = expect_offense(<<~ERB)
          <% if !foo %>
             ^^^^^^^^^^ Invert the negated condition and swap the if-else branches.
            <p>a</p>
          <% else %>
            <p>b</p>
          <% end %>
        ERB

        expect(offenses.map(&:correctable?)).to eq [false]
        expect_no_corrections
      end
    end

    context "when a correction would merge conditionals containing HTML" do
      let(:cop_class) { RuboCop::Cop::Style::IfInsideElse }

      it "reports the offense as not correctable" do
        offenses = expect_offense(<<~ERB)
          <% if a %>
            <p>x</p>
          <% else %>
            <% if b %>
               ^^ Convert `if` nested inside `else` to `elsif`.
              <p>y</p>
            <% end %>
          <% end %>
        ERB

        expect(offenses.map(&:correctable?)).to eq [false]
        expect_no_corrections
      end
    end

    context "when a correction would remove blank lines in HTML" do
      let(:cop_class) { RuboCop::Cop::Layout::EmptyLines }

      it "reports the offense as not correctable" do
        offenses = expect_offense(<<~ERB)
          <p>a</p>


          ^{} Extra blank line detected.
          <p>b</p>
        ERB

        expect(offenses.map(&:correctable?)).to eq [false]
        expect_no_corrections
      end
    end
  end

  context "with the whole run of RuboCop" do
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
    # Herb/Linting is tested in herb_lint_spec.rb
    let(:rubocop_config) { RuboCop::Herb::Configuration.to_rubocop_config.merge("Herb/Linting" => { "Enabled" => false }) }
    let(:path) { "test.html.erb" }

    before do
      RuboCop::Herb::Configuration.setup({})
      RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
    end

    after do
      config.unlink
      RuboCop::Lsp::StdinRunner.ruby_extractors.shift
    end

    context "with Layout/SpaceAroundOperators offense in ERB with CRLF line endings" do
      let(:source) { "<div>\r\n  <%= x==1 %>\r\n</div>\r\n" }
      # Parser::Source::Buffer normalizes CRLF to LF, as it does for Ruby files
      let(:expected) { "<div>\n  <%= x == 1 %>\n</div>\n" }

      it "corrects the offense" do
        runner.run(path, source, { autocorrect: true })

        expect(runner.formatted_source).to eq expected
      end
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

      it "does not insert rubocop:todo comments with --disable-uncorrectable" do
        runner.run(path, source, { autocorrect: true, disable_uncorrectable: true })

        expect(runner.formatted_source).to eq corrected
      end
    end
  end
end
