# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ImmovableExpressionCollector do
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

    context "with the same Ruby code inside different open tags" do
      let(:code) do
        "<% if a %>\n  <input type=\"text\" <%= x %>>\n<% else %>\n  <input type=\"password\" <%= x %>>\n<% end %>"
      end

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 4..4] })
      end
    end

    context "with the same Ruby code followed by HTML in a branch" do
      let(:code) { "<% if a %>\n  <input <%= x %>>\n<% else %>\n  <%= x %>\n<% end %>" }

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 4..4] })
      end
    end

    context "with the same Ruby code preceded by HTML" do
      let(:code) { "<% if a %>\n  <p>a</p>\n  <%= x %>\n<% else %>\n  <p>b</p>\n  <%= x %>\n<% end %>" }

      it "disables nothing because the Ruby code can be moved after the conditional" do
        expect(subject).to eq({})
      end
    end

    context "with the same Ruby code followed by HTML" do
      let(:code) { "<% if a %>\n  <% x %>\n  <p>a</p>\n<% else %>\n  <% x %>\n  <p>b</p>\n<% end %>" }

      it "disables nothing because the Ruby code can be moved before the conditional" do
        expect(subject).to eq({})
      end
    end

    context "with the same Ruby code at the head of multiple expressions preceded by HTML" do
      let(:code) { "<% if a %>\n  (<%= x %>\n  <%= y %>)\n<% else %>\n  [<%= x %>\n  <%= z %>]\n<% end %>" }

      it "disables Style/IdenticalConditionalBranches at the head" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 5..5] })
      end
    end

    context "with the same Ruby code inside different short texts" do
      let(:code) { "<% if a %>\n  (<%= x %>)\n<% else %>\n  [<%= x %>]\n<% end %>" }

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 4..4] })
      end
    end

    context "with the same Ruby code inside open tags in elsif, when and in branches" do
      let(:code) do
        "<% if a %>\n  <input type=\"a\" <%= x %>>\n<% elsif b %>\n  <input type=\"b\" <%= x %>>\n" \
          "<% else %>\n  <input type=\"c\" <%= x %>>\n<% end %>\n" \
          "<% case a %>\n<% in 1 %>\n  <input type=\"a\" <%= x %>>\n<% else %>\n  <input type=\"b\" <%= x %>>\n" \
          "<% end %>\n" \
          "<% case a %>\n<% when 1 %>\n  <input type=\"a\" <%= x %>>\n<% else %>\n  <input type=\"b\" <%= x %>>\n" \
          "<% end %>"
      end

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq(
          { "Style/IdenticalConditionalBranches" => [2..2, 4..4, 6..6, 10..10, 12..12, 16..16, 18..18] }
        )
      end
    end

    context "with the same multi-line Ruby code followed by HTML in a branch" do
      let(:code) do
        <<~ERB
          <% if a %>
            <input class="<% items.each do |i| %>
              <%= i %>
            <% end %>">
          <% else %>
            <% items.each do |i| %>
              <%= i %>
            <% end %>
          <% end %>
        ERB
      end

      it "disables Style/IdenticalConditionalBranches only at the first line of the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 6..6] })
      end
    end

    context "with the same Ruby code in conditionals written on a single line" do
      let(:code) do
        "<% if a %><%= x %><% else %><%= x %><% end %>\n" \
          "<% case a %><% when 1 %><%= x %><% else %><%= x %><% end %>\n" \
          "<% case a %><% in 1 %><%= x %><% else %><%= x %><% end %>"
      end

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [1..1, 1..1, 2..2, 2..2, 3..3, 3..3] })
      end
    end

    context "with the same Ruby code on the first line of the conditional" do
      let(:code) { "<% if a %><%= x %>\n<% else %>\n<%= x %>\n<% end %>" }

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [1..1, 3..3] })
      end
    end

    context "with the same Ruby code at the head of multiple expressions on the first line of the conditional" do
      let(:code) { "<% if a %><% x %>\n<% y %>\n<% else %>\n<% x %>\n<% z %>\n<% end %>" }

      it "disables Style/IdenticalConditionalBranches at the head" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [1..1, 4..4] })
      end
    end

    context "with the same Ruby code on the last line of the conditional" do
      let(:code) { "<% if a %>\n<%= x %>\n<% else %><%= x %><% end %>" }

      it "disables Style/IdenticalConditionalBranches at the Ruby code" do
        expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 3..3] })
      end
    end

    context "with the same Ruby code in a ternary and an if with then on a single line" do
      let(:code) { "<%= a ? x : x %>\n<% if a then %><%= x %><% else %><%= x %><% end %>" }

      it "disables nothing because the cop does not autocorrect them" do
        expect(subject).to eq({})
      end
    end

    context "with the same Ruby code on the lines other than the first and the last lines of the conditional" do
      let(:code) { "<% if a %>\n  <%= x %><% else %><%= x %>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with different Ruby code inside open tags" do
      let(:code) { "<% if a %>\n  <input <%= x %>>\n<% else %>\n  <input <%= y %>>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end

    context "with the same Ruby code inside open tags in a conditional without else" do
      let(:code) { "<% if a %>\n  <input <%= x %>>\n<% elsif b %>\n  <input <%= x %>>\n<% end %>" }

      it "disables nothing" do
        expect(subject).to eq({})
      end
    end
  end
end
