# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::NodeLocationCollector do
  describe ".collect" do
    let(:result) { described_class.collect(source, ast, html_visualization: false) }
    let(:ast) { Herb.parse(code) }
    let(:source) { RuboCop::Herb::Source.new(path: "test.html.erb", code:) }

    describe "erb_locations" do
      subject(:erb_locations) { result.erb_locations }

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

    describe "erb_max_columns" do
      subject(:erb_max_columns) { result.erb_max_columns }

      context "with single ERB tag" do
        let(:code) { "  <%= hello %>" }

        it "records the column of the ERB tag" do
          expect(erb_max_columns[1]).to eq(2)
        end
      end

      context "with multiple ERB tags on different lines" do
        let(:code) { "<%= a %>\n    <%= b %>\n  <%= c %>" }

        it "records the column for each line" do
          expect(erb_max_columns[1]).to eq(0)
          expect(erb_max_columns[2]).to eq(4)
          expect(erb_max_columns[3]).to eq(2)
        end
      end

      context "with multiple ERB tags on the same line" do
        let(:code) { "<%= a %>  <%= b %>" }

        it "records the maximum column" do
          expect(erb_max_columns[1]).to eq(10)
        end
      end

      context "with comment ERB tag" do
        let(:code) { "<%# comment %>" }

        it "does not record comment tags" do
          expect(erb_max_columns).to be_empty
        end
      end

      context "with mixed ERB tags including comment" do
        let(:code) { "<%= a %><%# comment %>" }

        it "only records non-comment tags" do
          expect(erb_max_columns[1]).to eq(0)
        end
      end
    end

    describe "html_block_positions" do
      subject(:html_block_positions) { result.html_block_positions }

      context "with HTML element containing ERB and close tag" do
        # <div class="x"> is 15 bytes, "div { " is 6 bytes - fits
        let(:code) { "<div class=\"x\"><%= hello %></div>" }

        it "collects the open tag position" do
          expect(html_block_positions).to eq Set[0]
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
          expect(html_block_positions).to eq Set[0]
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
          # <div class="a"> at position 0, <span class="b"> at position 15
          expect(html_block_positions).to eq Set[0, 15]
        end
      end

      context "with multiple HTML elements" do
        let(:code) { "<div class=\"a\"><%= a %></div><span class=\"b\"><%= b %></span>" }

        it "collects positions for all qualifying elements" do
          # <div class="a"> at 0, <span class="b"> at 29
          expect(html_block_positions).to eq Set[0, 29]
        end
      end
    end

    describe "tags" do
      subject(:tags) { result.tags }

      context "when html_visualization is disabled" do
        let(:result) { described_class.collect(source, ast, html_visualization: false) }

        context "with ERB tag only" do
          let(:code) { "<%= hello %>" }

          it "collects ERB tag with restore_source: false" do
            expect(tags.size).to eq(1)
            expect(tags[0].restore_source).to be false
          end
        end

        context "with HTML element containing ERB" do
          let(:code) { "<div><%= hello %></div>" }

          it "collects only ERB tag" do
            expect(tags.size).to eq(1)
            expect(tags.keys).to eq([5]) # ERB position
          end
        end
      end

      context "when html_visualization is enabled" do
        let(:result) { described_class.collect(source, ast, html_visualization: true) }

        context "with HTML element containing ERB" do
          let(:code) { "<div class=\"x\"><%= hello %></div>" }

          it "collects ERB tag and HTML tags" do
            # open_tag at 0, ERB at 15, close_tag at 27
            expect(tags.keys.sort).to eq [0, 15, 27]
          end

          it "sets restore_source correctly" do
            expect(tags[15].restore_source).to be false # ERB
            expect(tags[0].restore_source).to be true   # open_tag
            expect(tags[27].restore_source).to be true  # close_tag
          end
        end

        context "with HTML element without ERB" do
          let(:code) { "<div class=\"x\">text</div>" }

          it "collects the whole element and text node" do
            # element at 0, text "text" at 15
            expect(tags.keys.sort).to eq [0, 15]
            expect(tags[0].restore_source).to be true
            expect(tags[15].restore_source).to be true
          end
        end

        context "with HTML element containing ERB in attributes" do
          let(:code) { "<div class=\"<%= cls %>\">text</div>" }

          it "does not collect open_tag (contains ERB)" do
            # open_tag contains ERB, so it should not be recorded
            # ERB at 12, text at 24, close_tag at 28
            expect(tags.keys.sort).to eq [12, 24, 28]
          end
        end

        context "with text node" do
          let(:code) { "<div>hello</div>" }

          it "collects text node tag" do
            # element at 0, text "hello" at 5
            expect(tags.keys.sort).to eq [0, 5]
            expect(tags[5].restore_source).to be true
          end
        end

        context "with text node containing multi-byte characters" do
          let(:code) { "<div>こんにちは</div>" }

          it "does not collect text node tag" do
            # Only element at 0, multi-byte text is not recorded
            expect(tags.keys).to eq [0]
          end
        end

        context "with HTML comment" do
          let(:code) { "<!-- comment -->" }

          it "collects HTML comment tag" do
            expect(tags.keys).to eq [0]
            expect(tags[0].restore_source).to be true
          end
        end

        context "with HTML comment containing ERB" do
          let(:code) { "<!-- <%= hello %> -->" }

          it "does not collect HTML comment tag" do
            # Comment contains ERB, so comment itself is not recorded
            # Only ERB at position 5 is recorded
            expect(tags.keys).to eq [5]
          end
        end

        context "with HTML comment containing multi-byte characters" do
          let(:code) { "<!-- こんにちは -->" }

          it "does not collect HTML comment tag" do
            expect(tags).to be_empty
          end
        end
      end
    end
  end
end
