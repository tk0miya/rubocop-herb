# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::TailExpressionCollector do
  describe ".collect" do
    subject(:collected_nodes) { described_class.collect(ast, html_block_positions, html_visualization:) }

    # Helper to extract byte positions from collected nodes for easier comparison
    let(:collected_positions) { collected_nodes.to_set { |n| n.tag_opening.range.from } }

    let(:ast) { Herb.parse(code) }
    let(:source) { RuboCop::Herb::Source.new(code:) }
    let(:html_block_positions) { node_locations.html_block_positions }

    context "when html_visualization is disabled" do
      let(:html_visualization) { false }
      let(:node_locations) { RuboCop::Herb::NodeLocationCollector.collect(source, ast, html_visualization:) }

      context "with output node in if block" do
        let(:code) { "<% if cond %><%= expr %><% end %>" }

        it "collects the output node as tail expression" do
          expect(collected_positions).to eq Set[13] # <%= expr %>
        end
      end

      context "with output node in unless block" do
        let(:code) { "<% unless cond %><%= expr %><% end %>" }

        it "collects the output node as tail expression" do
          expect(collected_positions).to eq Set[17] # <%= expr %>
        end
      end

      context "with output node in else block" do
        let(:code) { "<% if cond %><%= a %><% else %><%= b %><% end %>" }

        it "collects both branch tail expressions" do
          expect(collected_positions).to eq Set[13, 31] # <%= a %>, <%= b %>
        end
      end

      context "with output node in case-when block" do
        let(:code) { "<% case x %><% when 1 %><%= a %><% when 2 %><%= b %><% end %>" }

        it "collects tail expressions from each when branch" do
          expect(collected_positions).to eq Set[24, 44] # <%= a %>, <%= b %>
        end
      end

      context "with output node in begin-rescue-ensure block" do
        let(:code) { "<% begin %><%= a %><% rescue %><%= b %><% ensure %><% cleanup %><% end %>" }

        it "collects tail expressions from begin, rescue, and ensure" do
          expect(collected_positions).to eq Set[11, 31, 51] # <%= a %>, <%= b %>, <% cleanup %>
        end
      end

      context "with multiple output nodes in same block" do
        let(:code) { "<% if cond %><%= first %><%= second %><% end %>" }

        it "only collects the last one as tail expression" do
          expect(collected_positions).to eq Set[25] # <%= second %> only
        end
      end

      context "with output node in each block" do
        let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

        it "does not collect as tail expression (blocks don't return)" do
          expect(collected_nodes).to be_empty
        end
      end

      context "with output node in for loop" do
        let(:code) { "<% for item in items %><%= item %><% end %>" }

        it "does not collect as tail expression" do
          expect(collected_nodes).to be_empty
        end
      end

      context "with output node in while loop" do
        let(:code) { "<% while cond %><%= x %><% end %>" }

        it "does not collect as tail expression" do
          expect(collected_nodes).to be_empty
        end
      end

      context "with output node in until loop" do
        let(:code) { "<% until done %><%= x %><% end %>" }

        it "does not collect as tail expression" do
          expect(collected_nodes).to be_empty
        end
      end

      context "with nested if inside each" do
        let(:code) { "<% items.each do |item| %><% if item.valid? %><%= item %><% end %><% end %>" }

        it "collects tail expression from inner if" do
          expect(collected_positions).to eq Set[46] # <%= item %>
        end
      end

      context "with output node followed by if block" do
        let(:code) { "<% if outer %><%= hello %><% if inner %><%= world %><% end %><% end %>" }

        it "does not collect output node before nested if as tail expression" do
          # <%= hello %> is NOT a tail expression because <% if inner %>...<% end %> follows it
          # <%= world %> IS a tail expression of the inner if
          # The inner if block IS the tail expression of the outer if
          expect(collected_positions).to eq Set[26, 40] # <% if inner %>, <%= world %>
        end
      end

      context "with yield node in if block" do
        let(:code) { "<% if block_given? %><%= yield %><% end %>" }

        it "collects yield as tail expression" do
          expect(collected_positions).to eq Set[21] # <%= yield %>
        end
      end

      context "with execution tag (not output)" do
        let(:code) { "<% if cond %><% action %><% end %>" }

        it "collects execution tags as tail expressions" do
          expect(collected_positions).to eq Set[13] # <% action %>
        end
      end

      context "with output node inside HTML block with brace notation" do
        # HTML block with enough space for brace notation, but html_visualization is disabled
        # so HTML blocks don't create block contexts
        let(:code) { "<% if cond %><div class=\"x\"><%= name %></div><% end %>" }

        it "collects as tail expression" do
          expect(collected_positions).to eq Set[28] # <%= name %>
        end
      end

      context "with output node after HTML block" do
        let(:code) { "<% if cond %><div class=\"x\"><%= a %></div><%= b %><% end %>" }

        it "collects only the last ERB as tail expression" do
          expect(collected_positions).to eq Set[42] # <%= b %> only
        end
      end

      context "with output node wrapped in HTML element without attributes" do
        # HTML element without enough space for brace notation
        let(:code) { "<% if cond %><li><%= x %></li><% end %>" }

        it "collects as tail expression" do
          expect(collected_positions).to eq Set[17] # <%= x %>
        end
      end

      context "with output node wrapped in HTML element with attributes" do
        # HTML element with enough space for brace notation, but html_visualization is disabled
        let(:code) { "<% if cond %><li class=\"x\"><%= name %></li><% end %>" }

        it "collects as tail expression" do
          expect(collected_positions).to eq Set[27] # <%= name %>
        end
      end

      context "with if-else containing HTML elements with attributes" do
        let(:code) do
          ["<% if cond %>",
           "  <li class=\"a\"><%= x %></li>",
           "<% else %>",
           "  <li class=\"b\"><%= y %></li>",
           "<% end %>"].join("\n")
        end

        it "collects ERB as tail expressions" do
          expect(collected_positions).to eq Set[30, 71] # Both <%= x %> and <%= y %>
        end
      end

      context "with if-else containing HTML elements without attributes" do
        let(:code) do
          ["<% if cond %>",
           "  <li><%= x %></li>",
           "<% else %>",
           "  <li><%= y %></li>",
           "<% end %>"].join("\n")
        end

        it "collects ERB as tail expressions" do
          expect(collected_positions).to eq Set[20, 51] # Both are tail expressions
        end
      end
    end

    context "when html_visualization is enabled" do
      let(:html_visualization) { true }
      let(:node_locations) { RuboCop::Herb::NodeLocationCollector.collect(source, ast, html_visualization:) }

      context "with output node in if block" do
        let(:code) { "<% if cond %><%= expr %><% end %>" }

        it "collects the output node as tail expression" do
          expect(collected_positions).to eq Set[13] # <%= expr %>
        end
      end

      context "with output node in else block" do
        let(:code) { "<% if cond %><%= a %><% else %><%= b %><% end %>" }

        it "collects both branch tail expressions" do
          expect(collected_positions).to eq Set[13, 31] # <%= a %>, <%= b %>
        end
      end

      context "with output node in each block" do
        let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

        it "does not collect as tail expression (blocks don't return)" do
          expect(collected_nodes).to be_empty
        end
      end

      context "with output node inside HTML block with brace notation" do
        # HTML block with enough space for brace notation creates a block context
        let(:code) { "<% if cond %><div class=\"x\"><%= name %></div><% end %>" }

        it "collects HTML element as tail expression" do
          expect(collected_positions).to eq Set[13] # <div class="x">
        end
      end

      context "with output node after HTML block" do
        let(:code) { "<% if cond %><div class=\"x\"><%= a %></div><%= b %><% end %>" }

        it "collects only the ERB after HTML block as tail expression" do
          expect(collected_positions).to eq Set[42] # <%= b %> only
        end
      end

      context "with output node wrapped in HTML element without attributes" do
        # HTML element without brace notation but with closing tag
        # The closing tag (li0;) comes after the ERB, so ERB is not a tail expression
        let(:code) { "<% if cond %><li><%= x %></li><% end %>" }

        it "collects closing tag as tail expression" do
          expect(collected_positions).to eq Set[25] # </li>
        end
      end

      context "with output node wrapped in HTML element with attributes" do
        # HTML element with enough space for brace notation creates a block context
        let(:code) { "<% if cond %><li class=\"x\"><%= name %></li><% end %>" }

        it "collects HTML element as tail expression" do
          expect(collected_positions).to eq Set[13] # <li class="x">
        end
      end

      context "with if-else containing HTML elements with attributes" do
        let(:code) do
          ["<% if cond %>",
           "  <li class=\"a\"><%= x %></li>",
           "<% else %>",
           "  <li class=\"b\"><%= y %></li>",
           "<% end %>"].join("\n")
        end

        it "collects HTML elements as tail expressions" do
          expect(collected_positions).to eq Set[16, 57] # <li class="a">, <li class="b">
        end
      end

      context "with if-else containing HTML elements without attributes" do
        let(:code) do
          ["<% if cond %>",
           "  <li><%= x %></li>",
           "<% else %>",
           "  <li><%= y %></li>",
           "<% end %>"].join("\n")
        end

        it "collects closing tags as tail expressions" do
          # The closing tags (</li>) are the last nodes in each branch
          expect(collected_positions).to eq Set[28, 59] # </li>, </li>
        end
      end
    end
  end
end
