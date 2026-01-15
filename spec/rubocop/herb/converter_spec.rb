# frozen_string_literal: true

require "spec_helper"

require "prism"

RSpec.describe RuboCop::Herb::Converter do
  shared_examples "a Ruby code extractor for ERB" do
    it "collects Ruby parts from ERB" do
      expect(subject).to eq(expected)
    end

    it "preserves byte lengths" do
      expect(subject.bytesize).to eq(source.bytesize)
    end

    it "generates valid Ruby code" do
      parse_result = Prism.parse(subject)
      expect(parse_result.errors).to be_empty
    end
  end

  describe "#convert" do
    subject { described_class.new.convert(source) }

    describe "with a content ERB tag" do
      let(:source) { "<div><%= user.name %></div>" }
      let(:expected) { "         user.name;        " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag" do
      let(:source) { "<div><%# user.name %></div>" }
      let(:expected) { "         user.name;        " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with if-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% if admin? %>",
         "    Hello, Admin!",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     if admin?;  ",
         "                 ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multiple ERB nodes on single line" do
      let(:source) { "<% if user %><%= user.name %><% end %>" }
      let(:expected) { "   if user;      user.name;     end;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end
  end
end
