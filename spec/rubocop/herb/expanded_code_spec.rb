# frozen_string_literal: true

RSpec.describe RuboCop::Herb::ExpandedCode do
  subject(:expanded_code) { described_class.new(ruby_code, markers) }

  def marker(from, to, name)
    RuboCop::Herb::HtmlMarker.new(range: RuboCop::Herb::CharRange.new(from:, to:), name:)
  end

  # The source positions of all the positions in the expanded code, including its end
  def source_positions
    (0..expanded_code.code.length).map { expanded_code.to_source_pos(_1) }
  end

  # The positions in the expanded code regarded as the semicolons of markers
  def marker_semicolons
    (0..expanded_code.code.length).select { expanded_code.marker_semicolon?(_1) }
  end

  context "without markers" do
    # source: "<%= x %>"
    let(:ruby_code) { "_ = x;  " }
    let(:markers) { [] }

    it "keeps the code and the positions" do
      expect(expanded_code.code).to eq "_ = x;  "
      expect(source_positions).to eq [0, 1, 2, 3, 4, 5, 6, 7, 8]
      expect(marker_semicolons).to eq []
    end
  end

  context "with a marker longer than its range" do
    # source: "a<%= x %>"
    let(:ruby_code) { " _ = x;  " }
    let(:markers) { [marker(0, 1, "_a")] }

    it "replaces the range with the code of the marker and maps the code to the range" do
      expect(expanded_code.code).to eq "_a;_ = x;  "
      # `_a` is mapped to the range (0...1), and `;` to the end of the range (1...1)
      expect(source_positions).to eq [0, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9]
      expect(marker_semicolons).to eq [2]
    end
  end

  context "with a marker as long as its range" do
    # source: "<%= x %>ab"
    let(:ruby_code) { "_ = x;    " }
    let(:markers) { [marker(8, 10, "_a")] }

    it "replaces the range with the code of the marker and maps the code to the range" do
      expect(expanded_code.code).to eq "_ = x;  _a;"
      # `_a` is mapped to the range (8...10), and `;` to the end of the range (10...10)
      expect(source_positions).to eq [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10]
      expect(marker_semicolons).to eq [10]
    end
  end

  context "with multiple markers given in any order" do
    # source: "<% if x %>a<% else %>bc<% end %>"
    let(:ruby_code) { "   if x;      else;       end;  " }
    let(:markers) { [marker(21, 23, "_a"), marker(10, 11, "_a")] }

    it "shifts the following markers and positions by the preceding markers" do
      expect(expanded_code.code).to eq "   if x;  _a;   else;  _a;   end;  "
      expect(source_positions).to eq [
        *0..9, 10, 11, 11, *11..20, 21, 22, 23, *23..32
      ]
      expect(marker_semicolons).to eq [12, 25]
    end
  end

  context "with markers of tags and text" do
    # source: "<div>abc<%= x %></div>"
    let(:ruby_code) { "        _ = x;        " }
    let(:markers) { [marker(0, 3, "div"), marker(5, 7, "_a"), marker(16, 19, "div")] }

    it "inserts the names of the markers with semicolons" do
      expect(expanded_code.code).to eq "div;  _a; _ = x;  div;   "
      expect(source_positions).to eq [
        0, 1, 2, 3, *3..4, 5, 6, 7, *7..15, 16, 17, 18, 19, *19..22
      ]
      expect(marker_semicolons).to eq [3, 8, 21]
    end
  end
end
