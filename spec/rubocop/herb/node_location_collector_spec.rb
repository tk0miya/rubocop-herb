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

      context "with a raw output ERB tag" do
        let(:code) { "<%== hello %>" }

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

      context "with an escaped ERB block containing an ERB tag" do
        let(:code) { "<%% items.each do |item| %><%= item %><%% end %>" }

        it "collects only the unescaped ERB tag" do
          expect(erb_locations.keys).to eq [27]
          expect(erb_locations.values.first.type).to eq(:output)
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
  end
end
