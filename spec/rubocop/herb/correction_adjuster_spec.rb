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

    context "when the correction edits an ERB comment to the end of the line" do
      # e.g. Lint/RedundantCopDisableDirective removing one of the cops with the whitespace after it,
      # which also covers the closing delimiter rendered as whitespace
      let(:source) { "<%# rubocop:disable Lint/Void, Lint/UselessAssignment %>\n<p>a</p>" }

      before { corrector.remove(range(29, 56)) }

      it { is_expected.to eq "<%# rubocop:disable Lint/Void %>\n<p>a</p>" }
    end

    context "when the correction replaces an ERB comment to the end of the line" do
      # e.g. Style/DirectiveScope rewriting the directive, whose text keeps the whitespace at the end of the comment
      let(:source) { "<%# rubocop:disable Lint/Void %>\n<p>a</p>" }

      before { corrector.replace(range(2, 32), "# rubocop:disable-next Lint/Void   ") }

      it { is_expected.to eq "<%# rubocop:disable-next Lint/Void %>\n<p>a</p>" }
    end

    context "when the correction replaces a whole ERB comment with ` # ` along with the delimiters around it" do
      # e.g. Lint/RedundantCopDisableDirective removing an unnecessary directive, which regards the closing delimiter
      # rendered as whitespace as more text in the comment
      let(:source) { "<%= x %><%# rubocop:disable Lint/Void %>\n<%= y %>" }

      before { corrector.replace(range(6, 40), " # ") }

      it { is_expected.to eq "<%= x %>\n<%= y %>" }
    end

    context "when the correction replaces a whole ERB comment on its own line with ` # ` to the next line" do
      let(:source) { "<div>\n\n  <%# rubocop:disable Lint/Void %>\n  <%= x %>\n</div>" }

      before { corrector.replace(range(11, 42), " # ") }

      it "removes the line of the ERB comment, keeping the indentation of the next line" do
        expect(subject).to eq "<div>\n\n  <%= x %>\n</div>"
      end
    end

    context "when the correction replaces a whole ERB comment following HTML with ` # ` along with the HTML" do
      # The HTML is rendered as whitespace in the Ruby code
      let(:source) { "<p>a</p> <%# rubocop:disable Lint/Void %>\n<%= x %>" }

      before { corrector.replace(range(2, 41), " # ") }

      it "removes the ERB comment with the whitespace before it, keeping the HTML" do
        expect(subject).to eq "<p>a</p>\n<%= x %>"
      end
    end

    context "when the correction replaces whitespace over an ERB comment followed by an ERB tag on the same line" do
      # The comment is rendered as whitespace, not as a Ruby comment, so it is not regarded as removed
      let(:source) { "<% foo(a,\n %><%# c %><% b) %>\n" }

      before { corrector.replace(range(10, 24), "       ") }

      it { is_expected.to be_nil }
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
