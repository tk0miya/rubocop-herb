# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ExtraSpacingCollector do
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

        it "disables Layout/ExtraSpacing at the line" do
          expect(subject).to eq({ "Layout/ExtraSpacing" => [1..1] })
        end
      end

      context "with spaces written in an ERB tag" do
        let(:code) { "<%= link_to  x %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end

      context "with spaces written in a multi-line ERB tag" do
        let(:code) { "<%\n  a =  1\n  b = 2 %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end
    end

    context "with HTML visualized as Ruby code" do
      let(:html_visualization) { true }

      context "with spaces in HTML" do
        let(:code) { "<div>  <%= x %></div>" }

        it "disables Layout/ExtraSpacing at the line" do
          expect(subject).to eq({ "Layout/ExtraSpacing" => [1..1] })
        end
      end
    end
  end
end
