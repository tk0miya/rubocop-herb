# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::HtmlOnlyLineCollector do
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

    # @rbs lines: Array[Range[Integer]]
    def disabled_at(lines) #: Hash[String, Array[Range[Integer]]]
      { described_class::COP_NAME => lines }
    end

    context "with lines without ERB tags" do
      let(:code) { "<div>\n  <p>x</p>\n</div>\n" }

      it "disables Layout/LineLength at the lines" do
        expect(subject).to eq disabled_at([1..1, 2..2, 3..3])
      end
    end

    context "with lines with ERB tags" do
      let(:code) { "<p><%= a %></p>\n<p>x</p>\n<%# comment %>\n" }

      it "disables Layout/LineLength except for the lines with ERB tags" do
        expect(subject).to eq disabled_at([2..2])
      end
    end

    context "with blank lines" do
      let(:code) { "<% a = 1 %>\n\n<p>x</p>\n\n<%= a %>\n" }

      it "disables Layout/LineLength at the blank lines" do
        expect(subject).to eq disabled_at([2..2, 3..3, 4..4])
      end
    end

    context "with a multi-line ERB tag" do
      let(:code) { "<p>x</p><%\n  a = 1\n\n  b = 2\n%><p>y</p>\n<p>z</p>\n" }

      it "disables Layout/LineLength except for the lines of the ERB tag" do
        expect(subject).to eq disabled_at([6..6])
      end
    end

    context "with an escaped ERB tag" do
      let(:code) { "<p><%%= a %></p>\n" }

      it "disables Layout/LineLength at the line" do
        expect(subject).to eq disabled_at([1..1])
      end
    end

    context "with ERB tags only" do
      let(:code) { "<% a = 1 %>\n<%= a %>\n" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end
  end
end
