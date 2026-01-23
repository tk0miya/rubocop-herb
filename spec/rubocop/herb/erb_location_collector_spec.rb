# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ErbLocationCollector do
  describe ".collect" do
    subject(:result) { described_class.collect(parse_result) }

    let(:parse_result) { Herb.parse(code) }
    let(:locations) { result.locations }

    context "with a content ERB tag" do
      let(:code) { "<% hello %>" }

      it "collects the ERB location with type :content" do
        expect(locations.size).to eq(1)
        expect(locations.keys.first).to eq(0)
        expect(locations.values.first.type).to eq(:content)
      end
    end

    context "with an output ERB tag" do
      let(:code) { "<%= hello %>" }

      it "collects the ERB location with type :output" do
        expect(locations.size).to eq(1)
        expect(locations.values.first.type).to eq(:output)
      end
    end

    context "with a comment ERB tag" do
      let(:code) { "<%# hello %>" }

      it "collects the ERB location with type :comment" do
        expect(locations.size).to eq(1)
        expect(locations.values.first.type).to eq(:comment)
      end
    end

    context "with multiple ERB tags" do
      let(:code) { "<%= foo %>\n<% bar %>\n<%# baz %>" }

      it "collects all ERB locations with positions as keys" do
        expect(locations.size).to eq(3)
        expect(locations.keys.sort).to eq([0, 11, 21])
      end
    end

    context "with ERB block tag" do
      let(:code) { "<% items.each do |item| %><%= item %><% end %>" }

      it "collects all ERB locations with type :block for block node" do
        expect(locations.size).to eq(3)
        expect(locations.values.first.type).to eq(:block)
      end
    end

    context "with ERB if tag" do
      let(:code) { "<% if true %><%= value %><% end %>" }

      it "sets type to :if for if node" do
        expect(locations.values.first.type).to eq(:if)
      end
    end

    context "with line and column information" do
      let(:code) { "text\n  <%= hello %>" }

      it "records correct line (1-indexed) and column (0-indexed)" do
        location = locations.values.first
        expect(location.line).to eq(2)
        expect(location.column).to eq(2)
      end
    end

    context "with range information" do
      let(:code) { "<%= hello %>" }

      it "records range from tag_opening to tag_closing" do
        location = locations.values.first
        expect(location.range.from).to eq(0)
        expect(location.range.to).to eq(12)
      end
    end
  end
end
