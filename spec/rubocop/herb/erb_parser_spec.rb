# frozen_string_literal: true

require "spec_helper"

RSpec.describe RuboCop::Herb::ErbParser do
  describe ".parse" do
    subject { described_class.parse("test.html.erb", code) }

    let(:code) do
      <<~ERB
        <div>
          <%= @name %>
        </div>
      ERB
    end

    it "returns a ParseResult with parsed data" do
      expect(subject).to be_a(RuboCop::Herb::ParseResult).and have_attributes(
        code:,
        ast: be_a(Herb::ParseResult)
      )
      expect(subject.source).to have_attributes(
        path: "test.html.erb",
        line_offsets: [0, 6, 21, 28]
      )
      expect(subject.erb_locations).not_to be_empty
    end
  end
end
