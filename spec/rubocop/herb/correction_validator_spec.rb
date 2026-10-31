# frozen_string_literal: true

RSpec.describe RuboCop::Herb::CorrectionValidator do
  describe "#valid?" do
    subject { described_class.new(conversion_result.parse_result).valid?(corrector) }

    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", source) }
    let(:buffer) { Parser::Source::Buffer.new("test.html.erb", source: conversion_result.ruby_code) }
    let(:corrector) { RuboCop::Cop::Corrector.new(buffer) }

    # @rbs from: Integer
    # @rbs to: Integer
    def range(from, to) #: Parser::Source::Range
      Parser::Source::Range.new(buffer, from, to)
    end

    context "when the correction changes Ruby code inside an ERB tag" do
      let(:source) { "<div><%= x==1 %></div>" }

      before { corrector.replace(range(10, 12), " == ") }

      it { is_expected.to be true }
    end

    context "when the correction removes HTML" do
      let(:source) { "<% if a %><p>x</p><% end %>" }

      before { corrector.remove(range(0, source.size)) }

      it { is_expected.to be false }
    end

    context "when the correction removes the closing delimiter of an ERB comment" do
      # The comment swallows the following tag
      let(:source) { "<%# note %>\n<% x %>" }

      before { corrector.remove(range(9, 11)) }

      it { is_expected.to be false }
    end

    context "when the correction removes `#` of an ERB comment" do
      # The text of the comment becomes code
      let(:source) { "<%# x %>" }

      before { corrector.remove(range(2, 3)) }

      it { is_expected.to be false }
    end

    context "when the correction changes code containing `<%` in an ERB tag" do
      let(:source) { %(<%= "<%"+x %>) }

      before { corrector.replace(range(8, 9), " + ") }

      it { is_expected.to be true }
    end

    context "when the correction removes an escaped ERB tag" do
      let(:source) { "<p><%% x %><%= y %></p>" }

      before { corrector.remove(range(3, 11)) }

      it { is_expected.to be false }
    end

    context "when the correction moves HTML into an ERB tag" do
      let(:source) { "<% if a %><p>x</p><% end %>" }

      before { corrector.remove(range(16, 20)) }

      it { is_expected.to be false }
    end

    context "when the correction changes whitespace inside HTML" do
      let(:source) { "<p>a</p>\n\n\n<p>b</p>\n<% x %>" }

      before { corrector.remove(range(9, 10)) }

      it { is_expected.to be false }
    end

    context "when the correction removes ERB tags along with whitespace around them" do
      let(:source) do
        <<~ERB
          <% if a %>
            <p>x</p>
          <% else %>
            <% if b %>
              <p>y</p>
            <% end %>
          <% end %>
        ERB
      end
      let(:corrected) do
        <<~ERB
          <% if a %>
            <p>x</p>
          <% elsif b %>
              <p>y</p>
          <% end %>
        ERB
      end

      before { corrector.replace(range(0, source.size), corrected) }

      it { is_expected.to be true }
    end

    context "when the correction moves the code of output tags into a code tag" do
      let(:source) { "<% if a %><%= x %><% else %><%= y %><% end %>" }

      before { corrector.replace(range(0, source.size), "<% _ = a ? x : y %>") }

      it { is_expected.to be false }
    end

    context "when the correction moves the code of an unescaped output tag into a code tag" do
      let(:source) { "<% if a %><%== x %><% end %>" }

      before { corrector.replace(range(0, source.size), "<% _ = x if a %>") }

      it { is_expected.to be false }
    end

    context "when the correction removes a code tag next to an output tag" do
      let(:source) { "<%= a %> <% %>" }

      before { corrector.replace(range(0, source.size), "<%= a  %>") }

      it { is_expected.to be true }
    end

    context "when the correction introduces a parse error" do
      let(:source) { "<% if a %><p>x</p><% end %>" }

      before { corrector.replace(range(21, 24), "en") }

      it { is_expected.to be false }
    end

    context "when the source already has parse errors" do
      let(:source) { "<% if a %><p>x</p>\n<%= x==1 %>" }

      before { corrector.replace(range(24, 26), " == ") }

      it { is_expected.to be true }
    end
  end
end
