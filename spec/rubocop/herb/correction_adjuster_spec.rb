# frozen_string_literal: true

RSpec.describe RuboCop::Herb::CorrectionAdjuster do
  let(:adjuster) { described_class.new(conversion_result.parse_result, conversion_result.ruby_code) }
  let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", source) }
  let(:buffer) { Parser::Source::Buffer.new("test.html.erb", source: conversion_result.ruby_code) }
  let(:corrector) { RuboCop::Cop::Corrector.new(buffer) }

  # @rbs from: Integer
  # @rbs to: Integer
  def range(from, to) #: Parser::Source::Range
    Parser::Source::Range.new(buffer, from, to)
  end

  # @rbs corrector: RuboCop::Cop::Corrector?
  def apply(corrector) #: String?
    return unless corrector

    erb_corrector = RuboCop::Cop::Corrector.new(Parser::Source::Buffer.new("test.html.erb", source:))
    erb_corrector.import!(corrector, offset: 0)
    erb_corrector.rewrite
  end

  describe "#trim" do
    subject { apply(adjuster.trim(corrector)) }

    context "when the correction removes code along with the delimiters before it" do
      let(:source) { "<p>a</p>\n<% 1 %>" }

      before { corrector.remove(range(8, 13)) }

      it { is_expected.to eq "<p>a</p>\n<% %>" }
    end

    context "when the correction removes code along with the delimiters after it" do
      let(:source) { "<% 1 %>\n<p>a</p>" }

      before { corrector.remove(range(3, 8)) }

      it { is_expected.to eq "<% %>\n<p>a</p>" }
    end

    context "when the correction stays inside an ERB tag" do
      let(:source) { "<% 1 %>" }

      before { corrector.remove(range(3, 4)) }

      it { is_expected.to be_nil }
    end

    context "when the correction spans multiple ERB tags" do
      let(:source) { "<% a %>\n<% b %>" }

      before { corrector.remove(range(4, 11)) }

      it { is_expected.to be_nil }
    end

    context "when the correction removes HTML rendered as whitespace before an ERB tag" do
      let(:source) { "<p>a</p><% 1 %>" }

      before { corrector.remove(range(4, 12)) }

      it { is_expected.to eq "<p>a</p><% %>" }
    end

    context "when the correction removes HTML rendered as code before an ERB tag" do
      let(:source) { "<p>a</p>\n<% 1 %>" }

      before { corrector.remove(range(1, 13)) }

      it { is_expected.to be_nil }
    end

    context "when the correction removes only whitespace along with the delimiters" do
      let(:source) { "<p>a</p>\n  <% x %>" }

      before { corrector.remove(range(9, 14)) }

      it { is_expected.to be_nil }
    end

    context "when the correction inserts code at the start of the content of an ERB tag" do
      let(:source) { "<%=foo%>" }

      before { corrector.insert_before(range(3, 3), "(") }

      it { is_expected.to be_nil }
    end

    context "when the correction inserts code at the end of the content of an ERB tag" do
      let(:source) { "<%=foo%>" }

      before { corrector.insert_before(range(6, 6), ")") }

      it { is_expected.to be_nil }
    end

    context "when the correction removes only whitespace outside ERB tags" do
      let(:source) { "<p>a</p>\n<% 1 %>" }

      before { corrector.remove(range(8, 10)) }

      it { is_expected.to be_nil }
    end
  end
end
