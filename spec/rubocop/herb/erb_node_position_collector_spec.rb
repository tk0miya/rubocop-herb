# frozen_string_literal: true

require "spec_helper"
require "herb"

RSpec.describe RuboCop::Herb::ErbNodePositionCollector do
  describe ".collect" do
    subject { described_class.collect(parse_result) }

    let(:parse_result) { Herb.parse(code) }

    context "with a content ERB tag" do
      let(:code) { "<%= @name %>" }

      it "collects the start position of the ERB node" do
        expect(subject).to eq(Set[0])
      end
    end

    context "with an execution ERB tag" do
      let(:code) { "<% @count += 1 %>" }

      it "collects the start position of the ERB node" do
        expect(subject).to eq(Set[0])
      end
    end

    context "with a comment ERB tag" do
      let(:code) { "<%# comment %>" }

      it "collects the start position of the ERB node" do
        expect(subject).to eq(Set[0])
      end
    end

    context "with multiple ERB tags" do
      let(:code) { "<%= @a %><%= @b %><%= @c %>" }

      it "collects all start positions" do
        expect(subject).to eq(Set[0, 9, 18])
      end
    end

    context "with ERB tags surrounded by HTML" do
      let(:code) { "<div><%= @name %></div>" }

      it "collects the start position of the ERB node" do
        expect(subject).to eq(Set[5])
      end
    end

    context "with if-end control structure" do
      let(:code) { "<% if cond %><%= @a %><% end %>" }

      it "collects start positions of all ERB nodes" do
        # if node at 0, content node at 13, end node at 22
        expect(subject).to eq(Set[0, 13, 22])
      end
    end

    context "with if-else-end control structure" do
      let(:code) { "<% if cond %><%= @a %><% else %><%= @b %><% end %>" }

      it "collects start positions of all ERB nodes" do
        # if node at 0, content at 13, else at 22, content at 32, end at 41
        expect(subject).to eq(Set[0, 13, 22, 32, 41])
      end
    end

    context "with unless-end control structure" do
      let(:code) { "<% unless cond %><%= @a %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 17, 26])
      end
    end

    context "with case-when-end control structure" do
      let(:code) { "<% case @x %><% when 1 %><%= @a %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 13, 25, 34])
      end
    end

    context "with for loop" do
      let(:code) { "<% for i in 1..3 %><%= i %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 19, 27])
      end
    end

    context "with while loop" do
      let(:code) { "<% while cond %><%= @a %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 16, 25])
      end
    end

    context "with until loop" do
      let(:code) { "<% until done %><%= @a %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 16, 25])
      end
    end

    context "with begin-rescue-ensure-end structure" do
      let(:code) { "<% begin %><%= @a %><% rescue %><%= @b %><% ensure %><%= @c %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 11, 20, 32, 41, 53, 62])
      end
    end

    context "with block iteration (each)" do
      let(:code) { "<% @items.each do |item| %><%= item %><% end %>" }

      it "collects start positions of all ERB nodes" do
        expect(subject).to eq(Set[0, 27, 38])
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

      it "collects start positions of all ERB nodes" do
        # if(8), each(27), content(61), inner end(82), outer end(94)
        expect(subject).to eq(Set[8, 27, 61, 82, 94])
      end
    end

    context "with no ERB tags" do
      let(:code) { "<div>Hello World</div>" }

      it "returns an empty set" do
        expect(subject).to eq(Set[])
      end
    end

    context "with multibyte characters" do
      let(:code) { "こんにちは<%= @name %>" }

      it "collects the correct byte position" do
        # "こんにちは" = 15 bytes (5 characters × 3 bytes)
        expect(subject).to eq(Set[15])
      end
    end
  end
end
