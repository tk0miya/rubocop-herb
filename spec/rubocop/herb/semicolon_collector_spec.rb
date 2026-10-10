# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::SemicolonCollector do
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

      context "with ERB tags on a line" do
        let(:code) { "<%= a %> <%= b %>" }

        it "disables Style/Semicolon at the line" do
          expect(subject).to eq({ "Style/Semicolon" => [1..1] })
        end
      end

      context "with semicolons written in a multi-line ERB tag" do
        let(:code) { "<%\n  a = 1; b = 2\n  c = 3 %>" }

        it "disables Style/Semicolon only at the line of the tag closing" do
          expect(subject).to eq({ "Style/Semicolon" => [3..3] })
        end
      end

      context "with semicolons written in an ERB tag on the line of the tag closing" do
        let(:code) { "<% a = 1; b = 2 %>" }

        it "disables Style/Semicolon at the line" do
          expect(subject).to eq({ "Style/Semicolon" => [1..1] })
        end
      end

      context "with semicolon written before the tag closing on its own line" do
        let(:code) { "<%\n  a = 1;\n%>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end
    end

    context "with HTML visualized as Ruby code" do
      let(:html_visualization) { true }

      context "with HTML" do
        let(:code) { "<p>x</p>" }

        it "disables Style/Semicolon at the line" do
          expect(subject).to eq({ "Style/Semicolon" => [1..1] })
        end
      end
    end
  end
end
