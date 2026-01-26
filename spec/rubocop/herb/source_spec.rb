# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::Source do
  let(:source) { described_class.new(path: "test.html.erb", code:) }

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

  describe "#location_to_range" do
    subject { source.location_to_range(location) }

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
