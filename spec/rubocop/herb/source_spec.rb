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

  describe "#byteslice" do
    subject { described_class.new(code).byteslice(range) }

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

  describe "#encoding" do
    subject { described_class.new(code).encoding }

    let(:code) { "hello" }

    it "returns the encoding of the source" do
      expect(subject).to eq(Encoding::UTF_8)
    end
  end
end
