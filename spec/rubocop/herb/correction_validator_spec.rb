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
