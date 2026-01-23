# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::NodeLocationCollector do
  describe ".collect" do
    subject(:result) { described_class.collect(parse_result) }

    let(:parse_result) { Herb.parse(code) }
    let(:erb_locations) { result.erb_locations }
    let(:html_block_positions) { result.html_block_positions }

    describe "ERB location collection" do
      context "with a content ERB tag" do
        let(:code) { "<% hello %>" }

        it "collects the ERB location with type :content" do
          expect(erb_locations.size).to eq(1)
          expect(erb_locations.keys.first).to eq(0)
          expect(erb_locations.values.first.type).to eq(:content)
        end
      end

      context "with an output ERB tag" do
        let(:code) { "<%= hello %>" }

        it "collects the ERB location with type :output" do
          expect(erb_locations.size).to eq(1)
          expect(erb_locations.values.first.type).to eq(:output)
        end
      end

      context "with a comment ERB tag" do
        let(:code) { "<%# hello %>" }

        it "collects the ERB location with type :comment" do
          expect(erb_locations.size).to eq(1)
          expect(erb_locations.values.first.type).to eq(:comment)
        end
      end

      context "with multiple ERB tags" do
        let(:code) { "<%= foo %>\n<% bar %>\n<%# baz %>" }

        it "collects all ERB locations with positions as keys" do
          expect(erb_locations.size).to eq(3)
          expect(erb_locations.keys.sort).to eq([0, 11, 21])
        end
      end

      context "with ERB block tag" do
        let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

        it "collects all ERB locations with type :block for block node" do
          expect(erb_locations.size).to eq(3)
          expect(erb_locations.values.first.type).to eq(:block)
        end
      end

      context "with ERB if tag" do
        let(:code) { "<% if true %><%= value %><% end %>" }

        it "sets type to :if for if node" do
          expect(erb_locations.values.first.type).to eq(:if)
        end
      end

      context "with line and column information" do
        let(:code) { "text\n  <%= hello %>" }

        it "records correct line (1-indexed) and column (0-indexed)" do
          location = erb_locations.values.first
          expect(location.line).to eq(2)
          expect(location.column).to eq(2)
        end
      end

      context "with range information" do
        let(:code) { "<%= hello %>" }

        it "records range from tag_opening to tag_closing" do
          location = erb_locations.values.first
          expect(location.range.from).to eq(0)
          expect(location.range.to).to eq(12)
        end
      end
    end

    describe "HTML block position collection" do
      context "with HTML element containing ERB and close tag" do
        # <div class="x"> is 15 bytes, "div { " is 6 bytes - fits
        let(:code) { "<div class=\"x\"><%= hello %></div>" }

        it "collects the open tag position" do
          expect(html_block_positions).to include(0)
        end
      end

      context "with short tag that cannot fit block notation" do
        # <div> is 5 bytes, needs 6 bytes for "div { " - doesn't fit
        let(:code) { "<div><%= hello %></div>" }

        it "does not collect the position" do
          expect(html_block_positions).to be_empty
        end
      end

      context "with void element (no close tag)" do
        let(:code) { "<br><%= hello %>" }

        it "does not collect the position" do
          expect(html_block_positions).to be_empty
        end
      end

      context "with ERB in open tag attributes" do
        let(:code) { "<div class=\"<%= cls %>\">text</div>" }

        it "collects the position" do
          expect(html_block_positions).to include(0)
        end
      end

      context "with HTML element without ERB" do
        let(:code) { "<div class=\"foo\">text</div>" }

        it "does not collect the position" do
          expect(html_block_positions).to be_empty
        end
      end

      context "with nested HTML elements containing ERB" do
        # Both <div class="a"> and <span class="b"> have enough space
        let(:code) { "<div class=\"a\"><span class=\"b\"><%= hello %></span></div>" }

        it "collects positions for elements that contain ERB" do
          # <div class="a"> at position 0
          expect(html_block_positions).to include(0)
          # <span class="b"> at position 15
          expect(html_block_positions).to include(15)
        end
      end

      context "with multiple HTML elements" do
        let(:code) { "<div class=\"a\"><%= a %></div><span class=\"b\"><%= b %></span>" }

        it "collects positions for all qualifying elements" do
          expect(html_block_positions.size).to eq(2)
          expect(html_block_positions).to include(0)  # <div class="a">
          expect(html_block_positions).to include(29) # <span class="b">
        end
      end
    end
  end
end
