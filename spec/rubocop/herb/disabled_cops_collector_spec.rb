# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::DisabledCopsCollector do
  describe ".collect" do
    subject { described_class.collect(Herb.parse(code)) }

    context "with if branch containing an HTML element" do
      let(:code) { "<% if a %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1] })
      end
    end

    context "with unless branch containing text" do
      let(:code) { "<% unless a %>\n  a\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the unless tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1] })
      end
    end

    context "with elsif branch containing an HTML comment" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% elsif b %>\n  <!-- b -->\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the elsif tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [3..3] })
      end
    end

    context "with if branches containing only an open tag or a close tag" do
      let(:code) { "<% if a %>\n  <a href=\"/\">\n<% end %>\ntext\n<% if a %>\n  </a>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at both if tags" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1, 5..5] })
      end
    end

    context "with if tag spanning multiple lines" do
      let(:code) { "<% if a &&\n     b %>\n  <p>a</p>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at all lines of the if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..2] })
      end
    end

    context "with if branch containing only whitespace" do
      let(:code) { "<% if a %>\n  \n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with if branch containing only ERB" do
      let(:code) { "<% if a %>\n  <%= a %>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with nested if branches containing an HTML element" do
      let(:code) { "<% if a %>\n  <% if b %>\n    <p>b</p>\n  <% end %>\n<% end %>" }

      it "disables Lint/EmptyConditionalBody at the inner if tag" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [2..2] })
      end
    end

    context "with if and elsif tags on a single line" do
      let(:code) { "<% if a %>a<% elsif b %><% end %>" }

      it "disables Style/OneLineConditional at the line" do
        expect(subject).to eq({ "Lint/EmptyConditionalBody" => [1..1], "Style/OneLineConditional" => [1..1] })
      end
    end

    context "with unless and else tags on a single line" do
      let(:code) { "<% unless a %><%= a %><% else %><%= b %><% end %>" }

      it "disables Style/OneLineConditional at the line" do
        expect(subject).to eq({ "Style/OneLineConditional" => [1..1] })
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
        expect(subject).to eq({ "Style/EmptyElse" => [3..3] })
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
  end
end
