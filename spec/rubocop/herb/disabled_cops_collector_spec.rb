# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::DisabledCopsCollector do
  describe ".collect" do
    subject { described_class.collect(Herb.parse(code)) }

    # Cops disabled at the if/unless tags of conditionals written across ERB tags
    def conditional_cops(*ranges)
      {
        "Style/IfWithSemicolon" => ranges,
        "Style/IfUnlessModifier" => ranges,
        "Style/ConditionalAssignment" => ranges,
        "Style/RedundantCondition" => ranges,
        "Style/Next" => ranges
      }
    end

    # Layout/IndentationWidth disabled from the first content to the first ERB tag of bodies
    def indentation_width(*ranges)
      { "Layout/IndentationWidth" => ranges }
    end

    # Layout/EndAlignment disabled at the end tags of conditionals and loops written across ERB tags
    def end_alignment(*ranges)
      { "Layout/EndAlignment" => ranges }
    end

    context "with if branch containing an HTML element" do
      let(:code) { "<% if a %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at the if tag" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1],
                                **conditional_cops(1..1),
                                **end_alignment(3..3),
                                **indentation_width(2..2)
                              })
      end
    end

    context "with unless branch containing text" do
      let(:code) { "<% unless a %>\n  a\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at the unless tag" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1],
                                **conditional_cops(1..1),
                                **end_alignment(3..3),
                                **indentation_width(2..2)
                              })
      end
    end

    context "with elsif branch containing an HTML comment" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% elsif b %>\n  <!-- b -->\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the elsif tag and the conditional cops at the if tag" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [3..3],
                                **conditional_cops(1..1),
                                **end_alignment(5..5),
                                **indentation_width(2..2, 4..4)
                              })
      end
    end

    context "with if branches containing only an open tag or a close tag" do
      let(:code) { "<% if a %>\n  <a href=\"/\">\n<% end %>\ntext\n<% if a %>\n  </a>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at both if tags" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1, 5..5],
                                **conditional_cops(1..1, 5..5),
                                **end_alignment(3..3, 7..7),
                                **indentation_width(2..2, 6..6)
                              })
      end
    end

    context "with if tag spanning multiple lines" do
      let(:code) { "<% if a &&\n     b %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody and the conditional cops at all lines of the if tag" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..2],
                                **conditional_cops(1..2),
                                **end_alignment(4..4),
                                **indentation_width(3..3)
                              })
      end
    end

    context "with if branch containing only whitespace" do
      let(:code) { "<% if a %>\n  \n<% end %>" }

      it "disables the conditional cops and the layout cops, but not Lint/EmptyConditionalBody" do
        expect(subject).to eq({ **conditional_cops(1..1), **end_alignment(3..3) })
      end
    end

    context "with if branch containing only ERB" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% end %>" }

      it "disables the conditional cops and the layout cops, but not Lint/EmptyConditionalBody" do
        expect(subject).to eq({ **conditional_cops(1..1), **end_alignment(3..3), **indentation_width(2..2) })
      end
    end

    context "with nested if branches containing an HTML element" do
      let(:code) { "<% if a %>\n  <% if b %>\n    <p>b</p>\n  <% end %>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the inner if tag and the conditional cops at both if tags" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [2..2],
                                **conditional_cops(1..1, 2..2),
                                **end_alignment(5..5, 4..4),
                                **indentation_width(2..2, 3..3)
                              })
      end
    end

    context "with if and elsif tags on a single line" do
      let(:code) { "<% if a %>a<% elsif b %><% end %>" }

      it "disables the conditional cops and Style/OneLineConditional at the line" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1],
                                "Style/OneLineConditional" => [1..1],
                                **conditional_cops(1..1),
                                **end_alignment(1..1),
                                **indentation_width(1..1)
                              })
      end
    end

    context "with unless and else tags on a single line" do
      let(:code) { "<% unless a %><%= a %><% else %><%= b %><% end %>" }

      it "disables the conditional cops and Style/OneLineConditional at the line" do
        expect(subject).to eq({
                                "Style/OneLineConditional" => [1..1],
                                **conditional_cops(1..1),
                                **end_alignment(1..1),
                                **indentation_width(1..1, 1..1)
                              })
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
        expect(subject).to eq({
                                "Style/EmptyElse" => [3..3],
                                **conditional_cops(1..1),
                                **end_alignment(5..5),
                                **indentation_width(2..2, 4..4)
                              })
      end
    end

    context "with when branch containing an HTML element" do
      let(:code) { "<% case a %>\n<% when 1 %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyWhen at the when tag and Style/ConditionalAssignment at the case tag" do
        expect(subject).to eq({
                                "Lint/EmptyWhen" => [2..2],
                                "Style/ConditionalAssignment" => [1..1],
                                **end_alignment(4..4),
                                **indentation_width(3..3)
                              })
      end
    end

    context "with when branch split from an ERB tag holding the case" do
      let(:code) { "<% case a when 1 %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyWhen and Style/ConditionalAssignment at the ERB tag" do
        expect(subject).to eq({
                                "Lint/EmptyWhen" => [1..1],
                                "Style/ConditionalAssignment" => [1..1],
                                **end_alignment(3..3),
                                **indentation_width(2..2)
                              })
      end
    end

    context "with case-in statement written across ERB tags" do
      let(:code) { "<% case a %>\n<% in 1 %>\n  <%= a %>\n<% in 2 %>\n  <%= b %>\n<% end %>" }

      it "disables Style/ConditionalAssignment at the case tag and Layout/EndAlignment at the end tag" do
        expect(subject).to eq({
                                "Style/ConditionalAssignment" => [1..1],
                                **end_alignment(6..6),
                                **indentation_width(3..3, 5..5)
                              })
      end
    end

    context "with case statement in a single ERB tag" do
      let(:code) { "<% case a when 1 then b else c end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with while and until loops written across ERB tags" do
      let(:code) { "<% while a %>\n  <p>a</p><% end %>\n<% until b %>\n  <p>b</p><% end %>" }

      it "disables Layout/EndAlignment at the end tags" do
        expect(subject).to eq({ **end_alignment(2..2, 4..4), **indentation_width(2..2, 4..4) })
      end
    end

    context "with end tag spanning multiple lines" do
      let(:code) { "<% while a %>\n  <p>a</p>\n<%\n  end\n%>" }

      it "disables Layout/EndAlignment at all lines of the end tag" do
        expect(subject).to eq({ **end_alignment(3..5), **indentation_width(2..2) })
      end
    end

    context "with body starting with HTML containing ERB" do
      let(:code) { "<% if a %>\n  <div>\n    <%= a %>\n  </div>\n<% end %>" }

      it "disables Layout/IndentationWidth from the HTML to the ERB tag" do
        expect(subject).to eq({
                                "Lint/EmptyConditionalBody" => [1..1],
                                **conditional_cops(1..1),
                                **end_alignment(5..5),
                                **indentation_width(2..3)
                              })
      end
    end

    context "with body starting with an ERB tag whose code starts at the next line" do
      let(:code) { "<% if a %>\n  <%\n    foo %>\n<% end %>" }

      it "disables Layout/IndentationWidth up to the line of the code" do
        expect(subject).to eq({ **conditional_cops(1..1), **end_alignment(4..4), **indentation_width(2..3) })
      end
    end

    context "with body starting with an ERB tag having only a Ruby comment" do
      let(:code) { "<% for x in a %>\n  <% # note %>\n  <%= x %>\n<% end %>" }

      it "disables Layout/IndentationWidth at the ERB tag after the comment" do
        expect(subject).to eq(indentation_width(3..3))
      end
    end

    context "with body starting with an empty ERB tag" do
      let(:code) { "<% for x in a %>\n  <% %>\n  <%= x %>\n<% end %>" }

      it "disables Layout/IndentationWidth at the ERB tag after the empty one" do
        expect(subject).to eq(indentation_width(3..3))
      end
    end

    context "with body starting with an ERB tag whose code follows a Ruby comment" do
      let(:code) { "<% for x in a %>\n  <% # note\n     foo %>\n<% end %>" }

      it "disables Layout/IndentationWidth up to the line of the code" do
        expect(subject).to eq(indentation_width(2..3))
      end
    end

    context "with body starting with an ERB comment followed by ERB" do
      let(:code) { "<% for x in a %>\n  <%# comment %>\n  <%= x %>\n<% end %>" }

      it "disables Layout/IndentationWidth at the ERB tag after the comment" do
        expect(subject).to eq(indentation_width(3..3))
      end
    end

    context "with body starting with an ERB comment followed by HTML" do
      let(:code) { "<% for x in a %>\n  <%# comment %>\n  <p>x</p>\n<% end %>" }

      it "disables Layout/IndentationWidth at the HTML after the comment" do
        expect(subject).to eq(indentation_width(3..3))
      end
    end

    context "with while loop in a single ERB tag" do
      let(:code) { "<% while a do b end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with block containing an HTML element" do
      let(:code) { "<% items.each do |item| %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyBlock at the block tag and Layout/BlockAlignment at the end tag" do
        expect(subject).to eq({
                                "Lint/EmptyBlock" => [1..1],
                                "Layout/BlockAlignment" => [3..3],
                                **indentation_width(2..2)
                              })
      end
    end

    context "with output block containing an HTML element" do
      let(:code) { "<%= form_with do |f| %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyBlock at the block tag and Layout/BlockAlignment at the end tag" do
        expect(subject).to eq({
                                "Lint/EmptyBlock" => [1..1],
                                "Layout/BlockAlignment" => [3..3],
                                **indentation_width(2..2)
                              })
      end
    end

    context "with block written across ERB tags on a single line" do
      let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

      it "disables Style/BlockDelimiters and Layout/BlockAlignment at the line" do
        expect(subject).to eq({
                                "Style/BlockDelimiters" => [1..1],
                                "Layout/BlockAlignment" => [1..1],
                                **indentation_width(1..1)
                              })
      end
    end

    context "with block in a single ERB tag" do
      let(:code) { "<% items.each do |item| item.save end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with rescue clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <p>x</p>\n<% rescue %>\n  <p>error</p>\n<% end %>" }

      it "disables Lint/SuppressedException at the rescue tag" do
        expect(subject).to eq({ "Lint/SuppressedException" => [3..3], **indentation_width(2..2, 4..4) })
      end
    end

    context "with subsequent rescue clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue A %>\n  <%= b %>\n<% rescue B %>\n  <p>error</p>\n<% end %>" }

      it "disables Lint/SuppressedException at the subsequent rescue tag" do
        expect(subject).to eq({ "Lint/SuppressedException" => [5..5], **indentation_width(2..2, 4..4, 6..6) })
      end
    end

    context "with ensure clause containing an HTML element" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% ensure %>\n  <p>done</p>\n<% end %>" }

      it "disables Lint/EmptyEnsure at the ensure tag" do
        expect(subject).to eq({ "Lint/EmptyEnsure" => [3..3], **indentation_width(2..2, 4..4) })
      end
    end

    context "with rescue and ensure clauses without any content" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue %>\n<% ensure %>\n<% end %>" }

      it "disables only Layout/IndentationWidth at the body of begin" do
        expect(subject).to eq(indentation_width(2..2))
      end
    end

    context "with rescue and ensure clauses containing only ERB" do
      let(:code) { "<% begin %>\n  <%= a %>\n<% rescue %>\n  <%= b %>\n<% ensure %>\n  <%= c %>\n<% end %>" }

      it "disables only Layout/IndentationWidth at the bodies" do
        expect(subject).to eq(indentation_width(2..2, 4..4, 6..6))
      end
    end

    context "with else branch, when branch and block containing only ERB" do
      let(:code) do
        "<% case a %>\n<% when 1 %>\n  <%= a %>\n<% else %>\n  <%= b %>\n<% end %>\n" \
          "<% items.each do |item| %>\n  <%= item %>\n<% end %>"
      end

      it "disables Style/ConditionalAssignment and the layout cops, but not the cops for empty bodies" do
        expect(subject).to eq({
                                "Style/ConditionalAssignment" => [1..1],
                                **end_alignment(6..6),
                                "Layout/BlockAlignment" => [9..9],
                                **indentation_width(3..3, 5..5, 8..8)
                              })
      end
    end

    context "with HTML element containing ERB" do
      let(:code) { "<div class=\"a\">\n  <%= x %>\n</div>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end
  end
end
