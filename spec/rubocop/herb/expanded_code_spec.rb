# frozen_string_literal: true

RSpec.describe RuboCop::Herb::ExpandedCode do
  subject(:expanded_code) { described_class.new(ruby_code, short_text_ranges) }

  def range(from, to)
    RuboCop::Herb::CharRange.new(from:, to:)
  end

  # The source positions of all the positions in the expanded code, including its end
  def source_positions
    (0..expanded_code.code.length).map { expanded_code.to_source_pos(_1) }
  end

  # The positions in the expanded code regarded as the semicolons of markers
  def marker_semicolons
    (0..expanded_code.code.length).select { expanded_code.marker_semicolon?(_1) }
  end

  context "without short texts" do
    # source: "<%= x %>"
    let(:ruby_code) { "_ = x;  " }
    let(:short_text_ranges) { [] }

    it "keeps the code and the positions" do
      expect(expanded_code.code).to eq "_ = x;  "
      expect(source_positions).to eq [0, 1, 2, 3, 4, 5, 6, 7, 8]
      expect(marker_semicolons).to eq []
    end
  end

  context "with a short text of 1 character" do
    # source: "a<%= x %>"
    let(:ruby_code) { " _ = x;  " }
    let(:short_text_ranges) { [range(0, 1)] }

    it "replaces the text with the marker and maps the marker to the text" do
      expect(expanded_code.code).to eq "_a;_ = x;  "
      # `_a` is mapped to the text (0...1), and `;` to the end of the text (1...1)
      expect(source_positions).to eq [0, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      expect(marker_semicolons).to eq [2]
    end
  end

  context "with a short text of 2 characters" do
    # source: "<%= x %>ab"
    let(:ruby_code) { "_ = x;    " }
    let(:short_text_ranges) { [range(8, 10)] }

    it "replaces the text with the marker and maps the marker to the text" do
      expect(expanded_code.code).to eq "_ = x;  _a;"
      # `_a` is mapped to the text (8...10), and `;` to the end of the text (10...10)
      expect(source_positions).to eq [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10]
      expect(marker_semicolons).to eq [10]
    end
  end

  context "with multiple short texts given in any order" do
    # source: "<% if x %>a<% else %>bc<% end %>"
    let(:ruby_code) { "   if x;      else;       end;  " }
    let(:short_text_ranges) { [range(21, 23), range(10, 11)] }

    it "shifts the following markers and positions by the preceding markers" do
      expect(expanded_code.code).to eq "   if x;  _a;   else;  _a;   end;  "
      expect(source_positions).to eq [
        *0..9, 10, 11, 11, *11..20, 21, 22, 23, *23..32
      ]
      expect(marker_semicolons).to eq [12, 25]
    end
  end
end
