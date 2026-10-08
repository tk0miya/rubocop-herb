# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ParseResult do
  let(:parse_result) { RuboCop::Herb::ErbParser.parse("test.html.erb", code) }

  describe "#byteslice" do
    subject { parse_result.byteslice(range) }

    context "with ASCII characters" do
      let(:code) { "hello\nworld\nfoo" }
      let(:range) { Herb::Range.new(0, 5) }

      it "extracts substring by byte range" do
        expect(subject).to eq("hello")
      end

      context "when spanning multiple lines" do
        let(:range) { Herb::Range.new(0, 11) }

        it "extracts substring spanning multiple lines" do
          expect(subject).to eq("hello\nworld")
        end
      end

      context "when extracting from middle" do
        let(:range) { Herb::Range.new(1, 4) }

        it "extracts substring from middle" do
          expect(subject).to eq("ell")
        end
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\nworld" }
      let(:range) { Herb::Range.new(0, 15) } # 5 chars × 3 bytes = 15 bytes

      it "extracts multibyte substring correctly" do
        expect(subject).to eq("こんにちは")
      end
    end
  end

  describe "#contains_html?" do
    subject { parse_result.contains_html?(RuboCop::Herb::CharRange.new(from, to)) }

    # "<% if a %>" = 0...10, "<p>x</p>" = 13...21, "<% else %>" = 22...32, "<% end %>" = 33...42
    let(:code) { "<% if a %>\n  <p>x</p>\n<% else %>\n<% end %>\n" }

    context "when the range covers HTML content" do
      let(:from) { 3 }
      let(:to) { 25 }

      it "returns true" do
        expect(subject).to be true
      end
    end

    context "when the range covers only ERB tags and whitespace" do
      let(:from) { 25 }
      let(:to) { 36 }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "when the range is empty" do
      let(:from) { 13 }
      let(:to) { 13 }

      it "returns false" do
        expect(subject).to be false
      end
    end

    context "with multibyte characters before the range" do
      # "<p>あ</p>" = 0...8, "<% if a %>" = 9...19
      let(:code) { "<p>あ</p>\n<% if a %>\n<% end %>\n" }
      let(:from) { 9 }
      let(:to) { 19 }

      it "uses character positions" do
        expect(subject).to be false
      end
    end
  end
end
