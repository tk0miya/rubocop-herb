# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::Source do
  describe "#code" do
    subject { described_class.new(code).code }

    let(:code) { "hello\nworld" }

    it "returns the original source code" do
      expect(subject).to eq("hello\nworld")
    end
  end

  describe "#lines" do
    subject { described_class.new(code).lines }

    context "with multiple lines" do
      let(:code) { "hello\nworld" }

      it "returns source split by lines" do
        expect(subject).to eq(%W[hello\n world])
      end
    end

    context "with single line without newline" do
      let(:code) { "hello" }

      it "returns single element array" do
        expect(subject).to eq(["hello"])
      end
    end

    context "with empty string" do
      let(:code) { "" }

      it "returns empty array" do
        expect(subject).to eq([])
      end
    end
  end

  describe "#offsets" do
    subject { described_class.new(code).offsets }

    context "with ASCII characters" do
      let(:code) { "hello\nworld" }

      it "returns character offsets for each line" do
        expect(subject).to eq([0, 6, 11])
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\n" }

      it "counts characters not bytes" do
        expect(subject).to eq([0, 6])
      end
    end
  end

  describe "#byte_offsets" do
    subject { described_class.new(code).byte_offsets }

    context "with ASCII characters" do
      let(:code) { "hello\nworld" }

      it "returns byte offsets for each line" do
        expect(subject).to eq([0, 6, 11])
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\n" } # 5 chars = 15 bytes + 1 newline

      it "counts bytes not characters" do
        expect(subject).to eq([0, 16])
      end
    end
  end

  describe "#slice" do
    subject { described_class.new(code).slice(start_line, start_column, end_line, end_column) }

    let(:start_line) { 1 }
    let(:start_column) { 0 }
    let(:end_line) { 1 }
    let(:end_column) { 5 }

    context "with ASCII characters" do
      let(:code) { "hello\nworld\nfoo" }

      it "extracts substring by line and column positions" do
        expect(subject).to eq("hello")
      end

      context "when spanning multiple lines" do
        let(:end_line) { 2 }

        it "extracts substring spanning multiple lines" do
          expect(subject).to eq("hello\nworld")
        end
      end

      context "when extracting from middle of line" do
        let(:start_column) { 1 }
        let(:end_column) { 4 }

        it "extracts substring from middle of line" do
          expect(subject).to eq("ell")
        end
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\nworld" }

      it "extracts multibyte substring correctly" do
        expect(subject).to eq("こんにちは")
      end
    end
  end

  describe "#byte_range" do
    subject { described_class.new(code).byte_range(start_line, start_column, end_line, end_column) }

    let(:start_line) { 1 }
    let(:start_column) { 0 }
    let(:end_line) { 1 }
    let(:end_column) { 5 }

    context "with ASCII characters" do
      let(:code) { "hello\nworld" }

      it "returns byte range for given positions" do
        expect(subject).to eq([0, 5])
      end

      context "when spanning multiple lines" do
        let(:end_line) { 2 }

        it "returns byte range spanning multiple lines" do
          expect(subject).to eq([0, 11])
        end
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは\nworld" }

      it "returns correct byte range for multibyte characters" do
        expect(subject).to eq([0, 15])
      end
    end
  end

  describe "#encoding" do
    subject { described_class.new(code).encoding }

    let(:code) { "hello" }

    it "returns the encoding of the source" do
      expect(subject).to eq(Encoding::UTF_8)
    end
  end
end
