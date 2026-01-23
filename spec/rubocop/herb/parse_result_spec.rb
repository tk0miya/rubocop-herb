# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ParseResult do
  let(:parse_result) { RuboCop::Herb::ErbParser.parse("test.html.erb", code) }

  describe "#byteslice" do
    subject { parse_result.byteslice(range) }

    let(:range) { instance_double(Herb::Range, from:, to:) }

    context "with ASCII characters" do
      let(:code) { "hello\nworld\nfoo" }
      let(:from) { 0 }
      let(:to) { 5 }

      it "extracts substring by byte range" do
        expect(subject).to eq("hello")
      end

      context "when spanning multiple lines" do
        let(:to) { 11 }

        it "extracts substring spanning multiple lines" do
          expect(subject).to eq("hello\nworld")
        end
      end

      context "when extracting from middle" do
        let(:from) { 1 }
        let(:to) { 4 }

        it "extracts substring from middle" do
          expect(subject).to eq("ell")
        end
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\nworld" }
      let(:from) { 0 }
      let(:to) { 15 } # 5 chars × 3 bytes = 15 bytes

      it "extracts multibyte substring correctly" do
        expect(subject).to eq("こんにちは")
      end
    end
  end

  describe "#location_to_range" do
    subject { parse_result.location_to_range(location) }

    let(:location) do
      instance_double(
        Herb::Location,
        start: instance_double(Herb::Position, line: start_line, column: start_column),
        end: instance_double(Herb::Position, line: end_line, column: end_column)
      )
    end

    context "with ASCII characters only" do
      let(:code) { "hello\nworld" }
      let(:start_line) { 2 }
      let(:start_column) { 0 }
      let(:end_line) { 2 }
      let(:end_column) { 5 }

      it "converts character-based location to byte range" do
        expect(subject.from).to eq(6) # "hello\n" = 6 bytes
        expect(subject.to).to eq(11) # "hello\nworld" = 11 bytes
      end
    end

    context "with multi-byte characters" do
      # "あいう" = 9 bytes, "text" = 4 bytes
      let(:code) { "あいうtext" }
      let(:start_line) { 1 }
      let(:start_column) { 3 } # After "あいう" (3 characters)
      let(:end_line) { 1 }
      let(:end_column) { 7 } # After "text" (7 characters total)

      it "converts character column to byte offset correctly" do
        expect(subject.from).to eq(9) # "あいう" = 3 chars × 3 bytes = 9 bytes
        expect(subject.to).to eq(13)  # "あいうtext" = 9 + 4 = 13 bytes
      end
    end

    context "with multi-byte characters on second line" do
      let(:code) { "hello\nあいうtext" }
      let(:start_line) { 2 }
      let(:start_column) { 3 } # After "あいう" (3 characters)
      let(:end_line) { 2 }
      let(:end_column) { 7 } # After "text" (7 characters total)

      it "converts character column to byte offset correctly" do
        expect(subject.from).to eq(15) # "hello\n" + "あいう" = 6 + 9 = 15 bytes
        expect(subject.to).to eq(19)   # "hello\nあいうtext" = 6 + 9 + 4 = 19 bytes
      end
    end
  end
end
