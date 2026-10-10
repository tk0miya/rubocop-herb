# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::IndentationConsistencyCollector do
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

      context "with statements in different ERB tags" do
        let(:code) { "<% a = 1 %>\n  <% b = 2 %>" }

        it "disables Layout/IndentationConsistency at the second statement" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [2..2] })
        end
      end

      context "with statements in begin written across ERB tags" do
        let(:code) { "<% begin %>\n  <% a = 1 %>\n    <% b = 2 %>\n<% end %>" }

        it "disables Layout/IndentationConsistency at the second statement" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [3..3] })
        end
      end

      context "with statements in a block written across ERB tags" do
        let(:code) { "<% items.each do |i| %>\n  <% a = i %>\n    <% b = i %>\n<% end %>" }

        it "disables Layout/IndentationConsistency at the second statement" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [3..3] })
        end
      end

      context "with statements in a single ERB tag" do
        let(:code) { "<% a = 1\n   b = 2 %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end

      context "with statements in the same ERB tag as the first statement and in another ERB tag" do
        let(:code) { "<% a = 1\n    b = 2 %>\n  <% c = 3 %>" }

        it "disables Layout/IndentationConsistency only at the statement in another ERB tag" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [3..3] })
        end
      end
    end

    context "with HTML visualized as Ruby code" do
      let(:html_visualization) { true }

      context "with a statement preceded by HTML" do
        let(:code) { "<p>a</p>\n  <% b = 1 %>" }

        it "disables Layout/IndentationConsistency at the statement" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [2..2] })
        end
      end

      context "with HTML preceded by a statement" do
        let(:code) { "<% a = 1 %>\n<p>x</p>" }

        it "disables Layout/IndentationConsistency at the HTML" do
          expect(subject).to eq({ "Layout/IndentationConsistency" => [2..2] })
        end
      end
    end
  end
end
