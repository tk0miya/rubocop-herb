# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::CommentIndentationCollector do
  describe ".collect" do
    subject { described_class.collect(processed_source, conversion_result.parse_result) }

    let(:conversion_result) do
      RuboCop::Herb::Converter.new(html_visualization:).convert("test.html.erb", code)
    end
    let(:processed_source) do
      RuboCop::Herb::ProcessedSource.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        parse_result: conversion_result.parse_result
      )
    end

    context "with HTML converted to whitespace" do
      let(:html_visualization) { false }

      context "with ERB comment followed by an ERB tag" do
        let(:code) { "<div>\n  <%# note %>\n    <%= x %>\n</div>" }

        it "disables Layout/CommentIndentation at the comment" do
          expect(subject).to eq({ "Layout/CommentIndentation" => [2..2] })
        end
      end

      context "with ERB tag having only a Ruby comment followed by an ERB tag" do
        let(:code) { "<% # note %>\n  <%= x %>" }

        it "disables Layout/CommentIndentation at the comment" do
          expect(subject).to eq({ "Layout/CommentIndentation" => [1..1] })
        end
      end

      context "with comment at the end of the template" do
        let(:code) { "<%= x %>\n  <% # note %>" }

        it "disables Layout/CommentIndentation at the comment" do
          expect(subject).to eq({ "Layout/CommentIndentation" => [2..2] })
        end
      end

      context "with comment followed by code in the same ERB tag" do
        let(:code) { "<% # note\n   x = 1 %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end

      context "with comment at the end of a line" do
        let(:code) { "<% x = 1 # note %>\n  <%= y %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end
    end

    context "with HTML visualized as Ruby code" do
      let(:html_visualization) { true }

      context "with comment followed by HTML" do
        let(:code) { "<% # note %>\n<p>x</p>" }

        it "disables Layout/CommentIndentation at the comment" do
          expect(subject).to eq({ "Layout/CommentIndentation" => [1..1] })
        end
      end
    end
  end
end
