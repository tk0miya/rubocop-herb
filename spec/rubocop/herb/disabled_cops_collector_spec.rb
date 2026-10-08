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
  end
end
