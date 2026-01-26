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
end
