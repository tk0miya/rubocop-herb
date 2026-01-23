# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::HtmlBlockCollector do
  describe ".collect" do
    subject { described_class.collect(ast, erb_locations) }

    let(:ast) { Herb.parse(code) }
    let(:erb_locations) { RuboCop::Herb::ErbLocationCollector.collect(ast).locations }

    context "with HTML element containing ERB and close tag" do
      # <div class="x"> is 15 bytes, "div { " is 6 bytes - fits
      let(:code) { "<div class=\"x\"><%= hello %></div>" }

      it "collects the open tag position" do
        expect(subject).to include(0)
      end
    end

    context "with short tag that cannot fit block notation" do
      # <div> is 5 bytes, needs 6 bytes for "div { " - doesn't fit
      let(:code) { "<div><%= hello %></div>" }

      it "does not collect the position" do
        expect(subject).to be_empty
      end
    end

    context "with void element (no close tag)" do
      let(:code) { "<br><%= hello %>" }

      it "does not collect the position" do
        expect(subject).to be_empty
      end
    end

    context "with ERB in open tag attributes" do
      let(:code) { "<div class=\"<%= cls %>\">text</div>" }

      it "collects the position" do
        expect(subject).to include(0)
      end
    end

    context "with HTML element without ERB" do
      let(:code) { "<div class=\"foo\">text</div>" }

      it "does not collect the position" do
        expect(subject).to be_empty
      end
    end

    context "with nested HTML elements containing ERB" do
      # Both <div class="a"> and <span class="b"> have enough space
      let(:code) { "<div class=\"a\"><span class=\"b\"><%= hello %></span></div>" }

      it "collects positions for elements that contain ERB" do
        # <div class="a"> at position 0
        expect(subject).to include(0)
        # <span class="b"> at position 15
        expect(subject).to include(15)
      end
    end

    context "with multiple HTML elements" do
      let(:code) { "<div class=\"a\"><%= a %></div><span class=\"b\"><%= b %></span>" }

      it "collects positions for all qualifying elements" do
        expect(subject.size).to eq(2)
        expect(subject).to include(0)  # <div class="a">
        expect(subject).to include(29) # <span class="b">
      end
    end
  end
end
