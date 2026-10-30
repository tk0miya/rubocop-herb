# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::TrailingWhitespaceCollector do
  describe ".collect" do
    subject { described_class.collect(processed_source, conversion_result.parse_result) }

    let(:conversion_result) do
      RuboCop::Herb::Converter.new.convert("test.html.erb", code)
    end
    let(:processed_source) do
      RuboCop::Herb::ProcessedSource.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        parse_result: conversion_result.parse_result
      )
    end

    context "with ERB tag at the end of a line" do
      let(:code) { "<%= a %>" }

      it "disables Layout/TrailingWhitespace at the line" do
        expect(subject).to eq({ "Layout/TrailingWhitespace" => [1..1] })
      end
    end

    context "with trailing whitespace written in an ERB tag" do
      let(:code) { "<%\n  a = 1  \n  b = 2 %>" }

      it "disables Layout/TrailingWhitespace except for the line in the ERB tag" do
        expect(subject).to eq({ "Layout/TrailingWhitespace" => [1..1, 3..3] })
      end
    end

    context "with trailing whitespace written in HTML" do
      let(:code) { "<p>x</p>  " }

      it "disables Layout/TrailingWhitespace at the line" do
        expect(subject).to eq({ "Layout/TrailingWhitespace" => [1..1] })
      end
    end

    context "with HTML at the end of a line" do
      let(:code) { "<% a = 1 %><p>x</p>" }

      # The text and the close tag following `p;` are rendered as whitespace
      it "disables Layout/TrailingWhitespace at the line" do
        expect(subject).to eq({ "Layout/TrailingWhitespace" => [1..1] })
      end
    end
  end
end
