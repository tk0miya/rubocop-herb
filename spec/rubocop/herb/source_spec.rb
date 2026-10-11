# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::Source do
  let(:source) { described_class.new(path: "test.html.erb", code:) }

  describe "#slice" do
    subject { source.slice(RuboCop::Herb::CharRange.new(from: 2, to: 5)) }

    context "with ASCII only" do
      let(:code) { "hello\nworld" }

      it { is_expected.to eq "llo" }
    end

    context "with multibyte characters" do
      let(:code) { "あいう\nえお" }

      it { is_expected.to eq "う\nえ" }
    end
  end

  describe "#byte_to_char_pos" do
    subject { source.byte_to_char_pos(byte_pos) }

    context "with ASCII only" do
      let(:code) { "hello\nworld\n" }

      # "hello\n" = 6 bytes, "world\n" = 6 bytes
      # line_byte_offsets = [0, 6, 12]
      # line_char_offsets = [0, 6, 12]

      context "when at start of file" do
        let(:byte_pos) { 0 }

        it { is_expected.to eq 0 }
      end

      context "when in middle of first line" do
        let(:byte_pos) { 3 }

        it { is_expected.to eq 3 }
      end

      context "when at start of second line" do
        let(:byte_pos) { 6 }

        it { is_expected.to eq 6 }
      end

      context "when in middle of second line" do
        let(:byte_pos) { 8 }

        it { is_expected.to eq 8 }
      end
    end

    context "with multibyte characters" do
      let(:code) { "あいう\nえお\n" }

      # "あいう\n" = 3*3 + 1 = 10 bytes, 4 chars
      # "えお\n" = 2*3 + 1 = 7 bytes, 3 chars
      # line_byte_offsets = [0, 10, 17]
      # line_char_offsets = [0, 4, 7]

      context "when at start of file" do
        let(:byte_pos) { 0 }

        it { is_expected.to eq 0 }
      end

      context "when after first character (あ)" do
        let(:byte_pos) { 3 }

        it { is_expected.to eq 1 }
      end

      context "when after second character (い)" do
        let(:byte_pos) { 6 }

        it { is_expected.to eq 2 }
      end

      context "when at start of second line" do
        let(:byte_pos) { 10 }

        it { is_expected.to eq 4 }
      end

      context "when after first character of second line (え)" do
        let(:byte_pos) { 13 }

        it { is_expected.to eq 5 }
      end
    end

    context "with mixed ASCII and multibyte" do
      let(:code) { "a日b本c\n" }

      # "a" = 1 byte, "日" = 3 bytes, "b" = 1 byte, "本" = 3 bytes, "c" = 1 byte, "\n" = 1 byte
      # Total: 10 bytes, 6 chars
      # Byte positions: a=0, 日=1-3, b=4, 本=5-7, c=8, \n=9

      context "when at 'a'" do
        let(:byte_pos) { 0 }

        it { is_expected.to eq 0 }
      end

      context "when after 'a' (at '日')" do
        let(:byte_pos) { 1 }

        it { is_expected.to eq 1 }
      end

      context "when after '日' (at 'b')" do
        let(:byte_pos) { 4 }

        it { is_expected.to eq 2 }
      end

      context "when after 'b' (at '本')" do
        let(:byte_pos) { 5 }

        it { is_expected.to eq 3 }
      end

      context "when after '本' (at 'c')" do
        let(:byte_pos) { 8 }

        it { is_expected.to eq 4 }
      end
    end
  end

  describe "#char_to_byte_pos" do
    subject { source.char_to_byte_pos(char_pos) }

    context "with ASCII only" do
      let(:code) { "hello\nworld\n" }
      let(:char_pos) { 8 }

      it { is_expected.to eq 8 }
    end

    context "with multibyte characters" do
      let(:code) { "あいう\nえお\n" }

      # "あいう\n" = 10 bytes, 4 chars
      # "えお\n" = 7 bytes, 3 chars

      context "when at start of file" do
        let(:char_pos) { 0 }

        it { is_expected.to eq 0 }
      end

      context "when after first character (あ)" do
        let(:char_pos) { 1 }

        it { is_expected.to eq 3 }
      end

      context "when at start of second line" do
        let(:char_pos) { 4 }

        it { is_expected.to eq 10 }
      end

      context "when after first character of second line (え)" do
        let(:char_pos) { 5 }

        it { is_expected.to eq 13 }
      end

      context "when at end of file" do
        let(:char_pos) { 7 }

        it { is_expected.to eq 17 }
      end
    end
  end

  describe "#char_pos" do
    subject { source.char_pos(line, column) }

    context "with ASCII characters only" do
      let(:code) { "hello\nworld" }
      let(:line) { 2 }
      let(:column) { 5 }

      it { is_expected.to eq 11 } # "hello\n" (6 chars) + "world" (5 chars)
    end

    context "with multi-byte characters" do
      let(:code) { "あいうtext" }
      let(:line) { 1 }
      let(:column) { 3 } # After "あいう" (3 characters, 9 bytes)

      it { is_expected.to eq 3 }
    end

    context "with multi-byte characters on second line" do
      let(:code) { "あいう\nあいうtext" }
      let(:line) { 2 }
      let(:column) { 3 } # After "あいう" on the second line

      it { is_expected.to eq 7 } # "あいう\n" (4 chars) + "あいう" (3 chars)
    end
  end
end
