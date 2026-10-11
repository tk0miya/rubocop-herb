# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::NodeLocationCollector do
  describe ".collect" do
    let(:result) { described_class.collect(source, ast) }
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

        it "sets type to :if for `if` node" do
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

    describe "erb_positions" do
      subject(:erb_positions) { result.erb_positions }

      context "with ERB tags inside and outside of an element" do
        let(:code) { "<%= a %><div><%= b %></div><%= c %>" }

        it "collects the start positions of the ERB tags in ascending order" do
          expect(erb_positions).to eq [0, 13, 27]
        end
      end

      context "with an open tag containing ERB visited twice (open and close tags in separate conditionals)" do
        let(:code) { "<% if a %><a href=\"<%= u %>\"><% end %>x<% if a %></a><% end %>" }

        it "collects each start position only once" do
          expect(erb_positions).to eq [0, 19, 29, 39, 53]
        end
      end
    end

    describe "erb_tag_ranges" do
      subject(:erb_tag_ranges) { result.erb_tag_ranges.map { [_1.from, _1.to] } }

      context "with ERB tags inside and outside of an element" do
        let(:code) { "<div><%= a %></div><% b %>" }

        it "collects the character ranges of the ERB tags in ascending order" do
          expect(erb_tag_ranges).to eq [[5, 13], [19, 26]]
        end
      end

      context "with multi-byte characters" do
        let(:code) { "あいう<%= a %>" }

        it "collects the ranges in characters" do
          expect(erb_tag_ranges).to eq [[3, 11]]
        end
      end
    end

    describe "tags" do
      subject(:tags) { result.tags }

      context "with ERB tag only" do
        let(:code) { "<%= hello %>" }

        it "collects ERB tag with restore_source: false" do
          expect(tags.size).to eq(1)
          expect(tags[0].restore_source).to be false
        end
      end

      context "with HTML element containing ERB" do
        let(:code) { "<div class=\"x\"><%= hello %></div>" }

        it "collects ERB tag and HTML tags with correct restore_source" do
          # open_tag at 0, ERB at 15, close_tag at 27
          expect(tags.keys.sort).to eq [0, 15, 27]
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

        it "does not collect the open_tag" do
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

      context "with an open tag without the close tag" do
        let(:code) { "<div class=\"a\">\n  <%= x %>" }

        it "collects the open tag" do
          # open tag at 0, ERB at 18
          expect(tags.transform_values(&:restore_source)).to eq({ 0 => true, 18 => false })
        end
      end

      context "with an open tag containing ERB without the close tag" do
        let(:code) { "<b <%= x %>>" }

        it "does not collect the open tag" do
          # Only ERB at 3 is recorded
          expect(tags.transform_values(&:restore_source)).to eq({ 3 => false })
        end
      end

      context "with open and close tags in separate conditionals" do
        let(:code) { "<% if a %><a href=\"/\"><% end %>link<% if a %></a><% end %>" }

        it "collects the open tag and the close tag" do
          # open tag at 10, text at 31, close tag at 45 and ERB tags
          expect(tags.transform_values(&:restore_source)).to eq(
            { 0 => false, 22 => false, 35 => false, 49 => false, 10 => true, 31 => true, 45 => true }
          )
        end
      end
    end
  end
end
