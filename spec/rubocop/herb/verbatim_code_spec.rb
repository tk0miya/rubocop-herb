# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::VerbatimCode do
  describe "#include?" do
    subject { described_class.new(conversion_result.parse_result).include?(range) }

    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", code) }
    let(:buffer) do
      Parser::Source::Buffer.new("test.html.erb", source: conversion_result.ruby_code)
    end
    let(:range) { Parser::Source::Range.new(buffer, from, to) }

    context "with the code in an ERB tag" do
      let(:code) { "<p><% a = 1 %></p>" }
      let(:from) { 6 }
      let(:to) { 11 }

      it { is_expected.to be true }
    end

    context "with the whole content of an ERB tag, from the tag opening to the tag closing" do
      let(:code) { "<%= foo%>" }
      let(:from) { 3 }
      let(:to) { 7 }

      it { is_expected.to be true }
    end

    context "with the tag opening of an output tag rendered as `_ =`" do
      let(:code) { "<%=foo%>" }
      let(:from) { 0 }
      let(:to) { 3 }

      it { is_expected.to be false }
    end

    context "with the closing delimiter rendered as a semicolon and whitespace" do
      let(:code) { "<% a = 1 %>" }
      let(:from) { 8 }
      let(:to) { 11 }

      it { is_expected.to be false }
    end

    context "with the whitespace before the closing delimiter, where a semicolon is rendered" do
      let(:code) { "<% case a %><% when 1 %><%= x %><% end %>" }
      let(:from) { 21 }
      let(:to) { 22 }

      it { is_expected.to be false }
    end

    context "with HTML" do
      let(:code) { "<div><%= a %></div>" }
      let(:from) { 0 }
      let(:to) { 5 }

      it { is_expected.to be false }
    end

    context "with a range spanning multiple ERB tags" do
      let(:code) { "<% if a %>x<% end %>" }
      let(:from) { 3 }
      let(:to) { 17 }

      it { is_expected.to be false }
    end

    context "with an empty range in the code of an ERB tag" do
      let(:code) { "<%\n  a = 1\n\n  b = 2\n%>" }
      let(:from) { 11 }
      let(:to) { 11 }

      it { is_expected.to be true }
    end

    context "with an empty range out of ERB tags" do
      let(:code) { "<%= a %>\n\n<%= b %>" }
      let(:from) { 9 }
      let(:to) { 9 }

      it { is_expected.to be false }
    end

    context "with the code after multi-byte characters" do
      let(:code) { "<p>日本語😀</p><% a = 1 %>" }
      let(:from) { 14 }
      let(:to) { 19 }

      it { is_expected.to be true }
    end

    context "with the code containing multi-byte characters" do
      let(:code) { "<p>日本語</p><% a = \"😀\" %>" }
      let(:from) { 13 }
      let(:to) { 20 }

      it { is_expected.to be true }
    end
  end

  describe "#code_range_of" do
    subject { described_class.new(conversion_result.parse_result).code_range_of(range) }

    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", code) }
    let(:buffer) do
      Parser::Source::Buffer.new("test.html.erb", source: conversion_result.ruby_code)
    end
    let(:range) { Parser::Source::Range.new(buffer, from, to) }

    context "with the code in the second ERB tag" do
      let(:code) { "<% a %><% b %>" }
      let(:from) { 10 }
      let(:to) { 11 }

      it { is_expected.to eq RuboCop::Herb::CharRange.new(from: 9, to: 12) }
    end

    context "with the code in an ERB tag after multi-byte characters" do
      let(:code) { "<p>日本語</p><% a %>" }
      let(:from) { 13 }
      let(:to) { 14 }

      it { is_expected.to eq RuboCop::Herb::CharRange.new(from: 12, to: 15) }
    end
  end
end
