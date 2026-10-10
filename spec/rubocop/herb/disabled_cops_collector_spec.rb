# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::DisabledCopsCollector do
  describe ".collect" do
    subject { described_class.collect(Herb.parse(code)) }

    # Cops disabled at the if/unless tags of conditionals written across ERB tags
    def conditional_cops(*ranges)
      { "Style/IfWithSemicolon" => ranges }
    end

    context "with if branch containing an HTML element" do
      let(:code) { "<% if a %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at the if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1], **conditional_cops(1..1) })
      end
    end

    context "with unless branch containing text" do
      let(:code) { "<% unless a %>\n  a\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at the unless tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1], **conditional_cops(1..1) })
      end
    end

    context "with elsif branch containing an HTML comment" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% elsif b %>\n  <!-- b -->\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the elsif tag and the conditional cops at the if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [3..3], **conditional_cops(1..1) })
      end
    end

    context "with if branches containing only an open tag or a close tag" do
      let(:code) { "<% if a %>\n  <a href=\"/\">\n<% end %>\ntext\n<% if a %>\n  </a>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at both if tags" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1, 5..5], **conditional_cops(1..1, 5..5) })
      end
    end

    context "with if tag spanning multiple lines" do
      let(:code) { "<% if a &&\n     b %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at all lines of the if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..2], **conditional_cops(1..2) })
      end
    end

    context "with if branch containing only whitespace" do
      let(:code) { "<% if a %>\n  \n<% end %>" }

      it "disables only the conditional cops at the if tag" do
        expect(subject).to eq(conditional_cops(1..1))
      end
    end

    context "with if branch containing only ERB" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% end %>" }

      it "disables only the conditional cops at the if tag" do
        expect(subject).to eq(conditional_cops(1..1))
      end
    end

    context "with nested if branches containing an HTML element" do
      let(:code) { "<% if a %>\n  <% if b %>\n    <p>b</p>\n  <% end %>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the inner if tag and the conditional cops at both if tags" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [2..2], **conditional_cops(1..1, 2..2) })
      end
    end

    context "with if and elsif tags on a single line" do
      let(:code) { "<% if a %>a<% elsif b %><% end %>" }

      it "disables the conditional cops and Style/OneLineConditional at the line" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1],
                                "Style/OneLineConditional" => [1..1],
                                **conditional_cops(1..1)
                              })
      end
    end

    context "with unless and else tags on a single line" do
      let(:code) { "<% unless a %><%= a %><% else %><%= b %><% end %>" }

      it "disables the conditional cops and Style/OneLineConditional at the line" do
        expect(subject).to eq({ "Style/OneLineConditional" => [1..1], **conditional_cops(1..1) })
      end
    end

    context "with if statement in a single ERB tag" do
      let(:code) { "<% if a then b else c end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with else branch containing an HTML element" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% else %>\n  <p>b</p>\n<% end %>" }

      it "disables Style/EmptyElse at the else tag" do
        expect(subject).to eq({ "Style/EmptyElse" => [3..3], **conditional_cops(1..1) })
      end
    end

    context "with when branch containing an HTML element" do
      let(:code) { "<% case a %>\n<% when 1 %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyWhen at the when tag" do
        expect(subject).to eq({ "Lint/EmptyWhen" => [2..2] })
      end
    end

    context "with when branch split from an ERB tag holding the case" do
      let(:code) { "<% case a when 1 %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyWhen at the ERB tag" do
        expect(subject).to eq({ "Lint/EmptyWhen" => [1..1] })
      end
    end

    context "with block containing an HTML element" do
      let(:code) { "<% items.each do |item| %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyBlock at the block tag" do
        expect(subject).to eq({ "Lint/EmptyBlock" => [1..1] })
      end
    end

    context "with output block containing an HTML element" do
      let(:code) { "<%= form_with do |f| %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyBlock at the block tag" do
        expect(subject).to eq({ "Lint/EmptyBlock" => [1..1] })
      end
    end

    context "with rescue clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <p>x</p>\n<% rescue %>\n  <p>error</p>\n<% end %>" }

      it "disables Lint/SuppressedException at the rescue tag" do
        expect(subject).to eq({ "Lint/SuppressedException" => [3..3] })
      end
    end

    context "with subsequent rescue clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue A %>\n  <%= b %>\n<% rescue B %>\n  <p>error</p>\n<% end %>" }

      it "disables Lint/SuppressedException at the subsequent rescue tag" do
        expect(subject).to eq({ "Lint/SuppressedException" => [5..5] })
      end
    end

    context "with ensure clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% ensure %>\n  <p>done</p>\n<% end %>" }

      it "disables Lint/EmptyEnsure at the ensure tag" do
        expect(subject).to eq({ "Lint/EmptyEnsure" => [3..3] })
      end
    end

    context "with rescue and ensure clauses without any content" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue %>\n<% ensure %>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with rescue and ensure clauses containing only ERB" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue %>\n  <%= b %>\n<% ensure %>\n  <%= c %>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with else branch, when branch and block containing only ERB" do
      let(:code) do
        "<% case a %>\n<% when 1 %>\n  <%= a %>\n<% else %>\n  <%= b %>\n<% end %>\n" \
          "<% items.each do |item| %>\n  <%= item %>\n<% end %>"
      end

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with HTML elements rendered as blocks" do
      subject { described_class.collect(ast, html_block_positions:) }

      let(:ast) { Herb.parse(code) }
      let(:source) { RuboCop::Herb::Source.new(path: "test.html.erb", code:) }
      let(:html_block_positions) do
        RuboCop::Herb::NodeLocationCollector.collect(source, ast, html_visualization: true).html_block_positions
      end

      context "with HTML element containing ERB" do
        let(:code) { "<div class=\"a\">\n  <%= x %>\n</div>" }

        it "disables the cops for the braces at the open tag and the close tag" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 3..3]
                                })
        end
      end

      context "with open tag spanning multiple lines" do
        let(:code) { "<div class=\"a\"\n     id=\"b\">\n  <%= x %>\n</div>" }

        it "disables the cops for the braces at the first line of the open tag and the close tag" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 4..4]
                                })
        end
      end

      context "with HTML element on a single line" do
        let(:code) { "<div class=\"a\"><%= x %></div>" }

        it "disables the cops for the braces, Style/SingleLineDoEndBlock and Layout/MultilineBlockLayout at the line" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1],
                                  "Style/SingleLineDoEndBlock" => [1..1],
                                  "Layout/MultilineBlockLayout" => [1..1]
                                })
        end
      end

      context "with HTML element whose content starts at the line of the open tag" do
        let(:code) { "<div class=\"a\"><%= x %>\n</div>" }

        it "disables the cops for the braces and Layout/MultilineBlockLayout" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 2..2],
                                  "Layout/MultilineBlockLayout" => [1..1]
                                })
        end
      end

      context "with open tag spanning multiple lines and content following it" do
        let(:code) { "<div class=\"a\"\n     id=\"b\"><%= x %>\n</div>" }

        it "disables the cops for the braces" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 3..3]
                                })
        end
      end

      context "with HTML element whose text content starts at the line of the open tag" do
        let(:code) { "<div class=\"a\"> text\n  <%= x %>\n</div>" }

        it "disables the cops for the braces and Layout/MultilineBlockLayout" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 3..3],
                                  "Layout/MultilineBlockLayout" => [1..1]
                                })
        end
      end

      context "with HTML element whose text content starts at the next line of the open tag" do
        let(:code) { "<div class=\"a\">\n  text\n  <%= x %>\n</div>" }

        it "disables the cops for the braces" do
          expect(subject).to eq({
                                  "Layout/SpaceBeforeBlockBraces" => [1..1],
                                  "Layout/SpaceInsideBlockBraces" => [1..1, 4..4]
                                })
        end
      end

      context "with HTML element too short to be rendered as a block" do
        let(:code) { "<div>\n  <%= x %>\n</div>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end
    end
  end
end
