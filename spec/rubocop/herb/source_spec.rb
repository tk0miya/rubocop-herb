# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::Source do
  let(:source) { described_class.new(path: "test.html.erb", code:) }

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
