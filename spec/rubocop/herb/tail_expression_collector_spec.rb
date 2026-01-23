# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::TailExpressionCollector do
  describe ".collect" do
    subject { described_class.collect(ast, html_block_positions) }

    let(:ast) { Herb.parse(code) }
    let(:erb_locations) { RuboCop::Herb::ErbLocationCollector.collect(ast).locations }
    let(:html_block_positions) { RuboCop::Herb::HtmlBlockCollector.collect(ast, erb_locations) }

    context "with output node in if block" do
      let(:code) { "<% if cond %><%= expr %><% end %>" }

      it "collects the output node as tail expression" do
        expect(subject).to eq Set[13] # <%= expr %>
      end
    end

    context "with output node in unless block" do
      let(:code) { "<% unless cond %><%= expr %><% end %>" }

      it "collects the output node as tail expression" do
        expect(subject).to eq Set[17] # <%= expr %>
      end
    end

    context "with output node in else block" do
      let(:code) { "<% if cond %><%= a %><% else %><%= b %><% end %>" }

      it "collects both branch tail expressions" do
        expect(subject).to eq Set[13, 31] # <%= a %>, <%= b %>
      end
    end

    context "with output node in case-when block" do
      let(:code) { "<% case x %><% when 1 %><%= a %><% when 2 %><%= b %><% end %>" }

      it "collects tail expressions from each when branch" do
        expect(subject).to eq Set[24, 44] # <%= a %>, <%= b %>
      end
    end

    context "with output node in begin-rescue-ensure block" do
      let(:code) { "<% begin %><%= a %><% rescue %><%= b %><% ensure %><% cleanup %><% end %>" }

      it "collects tail expressions from begin and rescue" do
        expect(subject).to eq Set[11, 31] # <%= a %>, <%= b %>
      end
    end

    context "with multiple output nodes in same block" do
      let(:code) { "<% if cond %><%= first %><%= second %><% end %>" }

      it "only collects the last one as tail expression" do
        expect(subject).to eq Set[25] # <%= second %> only
      end
    end

    context "with output node in each block" do
      let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

      it "does not collect as tail expression (blocks don't return)" do
        expect(subject).to be_empty
      end
    end

    context "with output node in for loop" do
      let(:code) { "<% for item in items %><%= item %><% end %>" }

      it "does not collect as tail expression" do
        expect(subject).to be_empty
      end
    end

    context "with output node in while loop" do
      let(:code) { "<% while cond %><%= x %><% end %>" }

      it "does not collect as tail expression" do
        expect(subject).to be_empty
      end
    end

    context "with output node in until loop" do
      let(:code) { "<% until done %><%= x %><% end %>" }

      it "does not collect as tail expression" do
        expect(subject).to be_empty
      end
    end

    context "with nested if inside each" do
      let(:code) { "<% items.each do |item| %><% if item.valid? %><%= item %><% end %><% end %>" }

      it "collects tail expression from inner if" do
        expect(subject).to eq Set[46] # <%= item %>
      end
    end

    context "with output node inside HTML block with brace notation" do
      # HTML block with enough space for brace notation
      let(:code) { "<% if cond %><div class=\"x\"><%= name %></div><% end %>" }

      it "does not collect as tail expression (HTML blocks don't return)" do
        expect(subject).to be_empty
      end
    end

    context "with output node after HTML block" do
      let(:code) { "<% if cond %><div class=\"x\"><%= a %></div><%= b %><% end %>" }

      it "collects only the ERB after HTML block as tail expression" do
        expect(subject).to eq Set[42] # <%= b %> only
      end
    end

    context "with yield node in if block" do
      let(:code) { "<% if block_given? %><%= yield %><% end %>" }

      it "collects yield as tail expression" do
        expect(subject).to eq Set[21] # <%= yield %>
      end
    end

    context "with execution tag (not output)" do
      let(:code) { "<% if cond %><% action %><% end %>" }

      it "does not collect execution tags" do
        expect(subject).to be_empty
      end
    end

    context "with output node wrapped in HTML element inside if" do
      # HTML element without enough space for brace notation
      let(:code) { "<% if cond %><li><%= x %></li><% end %>" }

      it "collects as tail expression (searches inside HTML)" do
        expect(subject).to eq Set[17] # <%= x %>
      end
    end

    context "with output node wrapped in HTML element with attributes inside if" do
      # HTML element with enough space for brace notation - ERB inside should NOT be tail expression
      let(:code) { "<% if cond %><li class=\"x\"><%= name %></li><% end %>" }

      it "does not collect as tail expression (HTML block with brace notation)" do
        expect(subject).to be_empty
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

      it "does not collect ERB inside HTML blocks as tail expressions" do
        expect(subject).to be_empty
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

      it "collects ERB as tail expressions (no brace notation)" do
        # Find positions: first <%= x %> and second <%= y %>
        expect(subject).to eq Set[20, 51] # Both are tail expressions
      end
    end
  end
end
