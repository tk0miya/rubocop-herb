# frozen_string_literal: true

RSpec.describe RuboCop::Herb::CommentConfig do
  let(:comment_config) { described_class.new(processed_source, disabled_cops:) }
  let(:processed_source) do
    RuboCop::AST::ProcessedSource.new(source, 3.3, "test.rb").tap do |ps|
      ps.config = RuboCop::ConfigLoader.default_configuration
      ps.registry = RuboCop::Cop::Registry.global
    end
  end
  let(:source) { "foo\nbar\nbaz\nqux\n" }
  let(:disabled_cops) { { "Style/StringLiterals" => [2..3] } }

  describe "#cop_enabled_at_line?" do
    subject { (1..4).map { comment_config.cop_enabled_at_line?(cop, _1) } }

    context "when the cop is given by name" do
      let(:cop) { "Style/StringLiterals" }

      it "returns false only at the lines in the disabled ranges" do
        expect(subject).to eq [true, false, false, true]
      end
    end

    context "when the cop is given as an instance" do
      let(:cop) { RuboCop::Cop::Style::StringLiterals.new }

      it "returns false only at the lines in the disabled ranges" do
        expect(subject).to eq [true, false, false, true]
      end
    end

    context "when the cop is not in the disabled cops" do
      let(:cop) { "Style/Semicolon" }

      it "returns true at all lines" do
        expect(subject).to eq [true, true, true, true]
      end
    end

    context "with rubocop:disable comments" do
      subject do
        %w[Style/StringLiterals Style/Semicolon].to_h do |cop|
          [cop, (1..4).map { comment_config.cop_enabled_at_line?(cop, _1) }]
        end
      end

      let(:source) { "foo # rubocop:disable Style/Semicolon\nbar\nbaz # rubocop:disable Style/StringLiterals\nqux\n" }
      let(:disabled_cops) { { "Style/StringLiterals" => [2..2] } }

      it "respects both the disabled ranges and the comments" do
        expect(subject).to eq({
                                "Style/StringLiterals" => [true, false, false, true],
                                "Style/Semicolon" => [false, true, true, true]
                              })
      end
    end
  end

  describe "#cop_enabled_at_lines?" do
    subject do
      spans.map do |first_line, last_line|
        comment_config.cop_enabled_at_lines?("Style/StringLiterals", first_line, last_line)
      end
    end

    context "when the spans are outside, overlapping and inside the disabled ranges" do
      let(:spans) { [[1, 1], [1, 2], [3, 4], [4, 4]] }

      it "returns false only for the spans overlapping the disabled ranges" do
        expect(subject).to eq [true, false, false, true]
      end
    end
  end

  describe "suppressing offenses" do
    subject { RuboCop::Cop::Commissioner.new([cop]).investigate(processed_source).offenses }

    let(:source) { %(a = "foo"\nb = "bar"\nc = "baz"\n) }
    let(:disabled_cops) { { "Style/StringLiterals" => [2..2] } }
    let(:cop) { RuboCop::Cop::Style::StringLiterals.new(processed_source.config) }

    before { processed_source.instance_variable_set(:@comment_config, comment_config) }

    it "marks offenses at the disabled lines as disabled" do
      expect(subject.map { [_1.line, _1.status] }).to eq [[1, :uncorrected], [2, :disabled], [3, :uncorrected]]
    end
  end
end
