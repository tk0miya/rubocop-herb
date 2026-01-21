# frozen_string_literal: true

require "spec_helper"
require "herb"

RSpec.describe RuboCop::Herb::ErbNodeRangeCollector do
  describe ".collect" do
    subject { described_class.collect(parse_result) }

    let(:parse_result) { Herb.parse(code) }

    context "with a content ERB tag" do
      let(:code) { "<%= @name %>" }

      it "collects the range of the ERB node" do
        expect(subject.keys).to eq([0])
        expect(subject[0]).to have_attributes(from: 0, to: 12)
      end
    end

    context "with an execution ERB tag" do
      let(:code) { "<% @count += 1 %>" }

      it "collects the range of the ERB node" do
        expect(subject.keys).to eq([0])
        expect(subject[0]).to have_attributes(from: 0, to: 17)
      end
    end

    context "with a comment ERB tag" do
      let(:code) { "<%# comment %>" }

      it "collects the range of the ERB node" do
        expect(subject.keys).to eq([0])
        expect(subject[0]).to have_attributes(from: 0, to: 14)
      end
    end

    context "with multiple ERB tags" do
      let(:code) { "<%= @a %><%= @b %><%= @c %>" }

      it "collects all ranges" do
        expect(subject.keys).to eq([0, 9, 18])
        expect(subject[0]).to have_attributes(from: 0, to: 9)
        expect(subject[9]).to have_attributes(from: 9, to: 18)
        expect(subject[18]).to have_attributes(from: 18, to: 27)
      end
    end

    context "with ERB tags surrounded by HTML" do
      let(:code) { "<div><%= @name %></div>" }

      it "collects the range of the ERB node" do
        expect(subject.keys).to eq([5])
        expect(subject[5]).to have_attributes(from: 5, to: 17)
      end
    end

    context "with if-end control structure" do
      let(:code) { "<% if cond %><%= @a %><% end %>" }

      it "collects ranges of all ERB nodes" do
        # if node at 0, content node at 13, end node at 22
        expect(subject.keys).to eq([0, 13, 22])
      end
    end

    context "with if-else-end control structure" do
      let(:code) { "<% if cond %><%= @a %><% else %><%= @b %><% end %>" }

      it "collects ranges of all ERB nodes" do
        # if node at 0, content at 13, else at 22, content at 32, end at 41
        expect(subject.keys).to eq([0, 13, 22, 32, 41])
      end
    end

    context "with unless-end control structure" do
      let(:code) { "<% unless cond %><%= @a %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 17, 26])
      end
    end

    context "with case-when-end control structure" do
      let(:code) { "<% case @x %><% when 1 %><%= @a %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 13, 25, 34])
      end
    end

    context "with for loop" do
      let(:code) { "<% for i in 1..3 %><%= i %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 19, 27])
      end
    end

    context "with while loop" do
      let(:code) { "<% while cond %><%= @a %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 16, 25])
      end
    end

    context "with until loop" do
      let(:code) { "<% until done %><%= @a %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 16, 25])
      end
    end

    context "with begin-rescue-ensure-end structure" do
      let(:code) { "<% begin %><%= @a %><% rescue %><%= @b %><% ensure %><%= @c %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 11, 20, 32, 41, 53, 62])
      end
    end

    context "with block iteration (each)" do
      let(:code) { "<% @items.each do |item| %><%= item %><% end %>" }

      it "collects ranges of all ERB nodes" do
        expect(subject.keys).to eq([0, 27, 38])
      end
    end

    context "with nested control structures" do
      let(:code) do
        [
          "<div>",
          "  <% if show? %>",
          "    <% @items.each do |item| %>",
          "      <%= item.name %>",
          "    <% end %>",
          "  <% end %>",
          "</div>"
        ].join("\n")
      end

      it "collects ranges of all ERB nodes" do
        # if(8), each(27), content(61), inner end(82), outer end(94)
        expect(subject.keys).to eq([8, 27, 61, 82, 94])
      end
    end

    context "with no ERB tags" do
      let(:code) { "<div>Hello World</div>" }

      it "returns an empty hash" do
        expect(subject).to eq({})
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは<%= @name %>" }

      it "collects the correct byte position and range" do
        # "こんにちは" = 15 bytes (5 characters × 3 bytes)
        expect(subject.keys).to eq([15])
        expect(subject[15]).to have_attributes(from: 15, to: 27)
      end
    end

    context "with HTML comment containing ERB" do
      let(:code) { "<!-- <%= @name %> -->" }

      it "collects the ERB range inside the comment" do
        expect(subject.keys).to eq([5])
        expect(subject[5]).to have_attributes(from: 5, to: 17)
      end
    end
  end
end
