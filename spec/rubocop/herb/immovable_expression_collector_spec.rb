# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ImmovableExpressionCollector do
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

      context "with the same Ruby code inside different HTML elements" do
        let(:code) { "<% if a %>\n  <p><%= x %></p>\n<% else %>\n  <div><%= x %></div>\n<% end %>" }

        it "disables Style/IdenticalConditionalBranches at the Ruby code" do
          expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [2..2, 4..4] })
        end
      end

      context "with the same Ruby code followed by HTML in a branch" do
        let(:code) { "<% if a %>\n  <p>a</p>\n  <%= x %>\n  <p>a</p>\n<% else %>\n  <%= x %>\n<% end %>" }

        it "disables Style/IdenticalConditionalBranches at the Ruby code" do
          expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [3..3, 6..6] })
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
        let(:code) do
          "<% if a %>\n  <p>a</p>\n  <% x %>\n  <% y %>\n<% else %>\n  <p>b</p>\n  <% x %>\n  <% z %>\n<% end %>"
        end

        it "disables Style/IdenticalConditionalBranches at the head" do
          expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [3..3, 7..7] })
        end
      end

      context "with the same Ruby code inside HTML elements in elsif, when and in branches" do
        let(:code) do
          "<% if a %>\n  <b><%= x %></b>\n<% elsif b %>\n  <i><%= x %></i>\n" \
            "<% else %>\n  <u><%= x %></u>\n<% end %>\n" \
            "<% case a %>\n<% in 1 %>\n  <b><%= x %></b>\n<% else %>\n  <i><%= x %></i>\n<% end %>\n" \
            "<% case a %>\n<% when 1 %>\n  <b><%= x %></b>\n<% else %>\n  <i><%= x %></i>\n<% end %>"
        end

        it "disables Style/IdenticalConditionalBranches at the Ruby code" do
          expect(subject).to eq(
            { "Style/IdenticalConditionalBranches" => [2..2, 4..4, 6..6, 10..10, 12..12, 16..16, 18..18] }
          )
        end
      end

      context "with the same multi-line Ruby code inside different HTML elements" do
        let(:code) do
          <<~ERB
            <% if a %>
              <div class="a">
              <% items.each do |i| %>
                <% if b %><%= i %><% else %><%= i %><% end %>
              <% end %>
              </div>
            <% else %>
              <div class="b">
              <% items.each do |i| %>
                <% if b %><%= i %><% else %><%= i %><% end %>
              <% end %>
              </div>
            <% end %>
          ERB
        end

        it "disables Style/IdenticalConditionalBranches only at the first line of the Ruby code" do
          expect(subject).to eq({ "Style/IdenticalConditionalBranches" => [3..3, 9..9] })
        end
      end

      context "with different Ruby code inside HTML elements" do
        let(:code) { "<% if a %>\n  <p><%= x %></p>\n<% else %>\n  <p><%= y %></p>\n<% end %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end

      context "with the same Ruby code inside HTML elements in a conditional without else" do
        let(:code) { "<% if a %>\n  <p><%= x %></p>\n<% elsif b %>\n  <p><%= x %></p>\n<% end %>" }

        it "disables nothing" do
          expect(subject).to eq({})
        end
      end
    end

    context "with HTML converted to Ruby identifiers" do
      let(:html_visualization) { true }

      context "with the same Ruby code inside different open tags" do
        let(:code) do
          "<% if a %>\n  <input type=\"text\" <%= x %>>\n<% else %>\n  <input type=\"password\" <%= x %>>\n<% end %>"
        end

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
    end
  end
end
