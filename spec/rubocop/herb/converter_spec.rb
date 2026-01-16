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

    # Basic ERB tags
    describe "with a content ERB tag" do
      let(:source) { "<div><%= user.name %></div>" }
      let(:expected) { "     _ = user.name;        " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag" do
      let(:source) { "<div><%# user.name %></div>" }
      let(:expected) { "       # user.name         " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with execution tag without output" do
      let(:source) { "<div><% @counter += 1 %></div>" }
      let(:expected) { "        @counter += 1;        " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Control structures
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

    describe "with unless-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% unless logged_in? %>",
         "    Please log in",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     unless logged_in?;  ",
         "                 ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with if-elsif-else-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% if admin? %>",
         "    Admin",
         "  <% elsif moderator? %>",
         "    Moderator",
         "  <% else %>",
         "    User",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     if admin?;  ",
         "         ",
         "     elsif moderator?;  ",
         "             ",
         "     else;  ",
         "        ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with case-when-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% case status %>",
         "  <% when :active %>",
         "    Active",
         "  <% when :inactive %>",
         "    Inactive",
         "  <% else %>",
         "    Unknown",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     case status;  ",
         "     when :active;  ",
         "          ",
         "     when :inactive;  ",
         "            ",
         "     else;  ",
         "           ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Loops
    describe "with block-ERB tags (each)" do
      let(:source) do
        ["<ul>",
         "  <% users.each do |user| %>",
         "    <li><%= user.name %></li>",
         "  <% end %>",
         "</ul>"].join("\n")
      end
      let(:expected) do
        ["    ",
         "     users.each do |user|;  ",
         "        _ = user.name;       ",
         "     end;  ",
         "     "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with block-ERB tags (times)" do
      let(:source) do
        ["<div>",
         "  <% 3.times do |i| %>",
         "    <p><%= i %></p>",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     3.times do |i|;  ",
         "       _ = i;      ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with for-ERB tags" do
      let(:source) do
        ["<ul>",
         "  <% for item in items %>",
         "    <li><%= item %></li>",
         "  <% end %>",
         "</ul>"].join("\n")
      end
      let(:expected) do
        ["    ",
         "     for item in items;  ",
         "        _ = item;       ",
         "     end;  ",
         "     "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with while-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% while condition %>",
         "    <p>Processing</p>",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     while condition;  ",
         "                     ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with until-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% until done %>",
         "    <p>Waiting</p>",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     until done;  ",
         "                  ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Exception handling
    describe "with begin-rescue-ensure-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% begin %>",
         "    <%= risky_operation %>",
         "  <% rescue StandardError => e %>",
         "    <%= e.message %>",
         "  <% ensure %>",
         "    <% cleanup %>",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     begin;  ",
         "        risky_operation;  ",
         "     rescue StandardError => e;  ",
         "        e.message;  ",
         "     ensure;  ",
         "       cleanup;  ",
         "     end;  ",
         "      "].join("\n")
      end

      # risky_operation and e.message don't have _ = because they're
      # before rescue/ensure (branch boundaries). cleanup is execution tag,
      # not output tag, so it never gets _ =.
      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Complex cases
    describe "with nested ERB tags" do
      let(:source) do
        ["<div>",
         "  <% if show_list? %>",
         "    <ul>",
         "      <% items.each do |item| %>",
         "        <li><%= item.name %></li>",
         "      <% end %>",
         "    </ul>",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "     if show_list?;  ",
         "        ",
         "         items.each do |item|;  ",
         "            _ = item.name;       ",
         "         end;  ",
         "         ",
         "     end;  ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multiple ERB nodes on single line" do
      let(:source) { "<% if user %><%= user.name %><% end %>" }
      let(:expected) { "   if user;  _ = user.name;     end;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with if-else containing output tags in branches" do
      let(:source) do
        ["<% if condition %>",
         "  <%= value1 %>",
         "<% else %>",
         "  <%= value2 %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   if condition;  ",
         "      value1;  ",
         "   else;  ",
         "  _ = value2;  ",
         "   end;  "].join("\n")
      end

      # value1 has no _ = because it's before else (branch boundary)
      # value2 has _ = because it's before end (not a branch boundary)
      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multiple content tags on same line" do
      let(:source) { "<p><%= first %> and <%= second %></p>" }
      let(:expected) { "   _ = first;       _ = second;      " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with raw output tag (-%>)" do
      let(:source) { "<div><%= value -%></div>" }
      let(:expected) { "     _ = value;         " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Comment filtering (ErbNodeCollector#filtered_nodes behavior)
    describe "with a comment ERB tag on its own line" do
      let(:source) do
        ["<%# comment %>",
         "<% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["  # comment   ",
         "   if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag followed by other ERB on the same line" do
      let(:source) do
        ["<%# comment %><% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["                 if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag on its own lines" do
      let(:source) do
        ["<%#",
         "  multiline",
         "  comment",
         "%>",
         "<% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "# multiline",
         "# comment",
         "  ",
         "   if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with sufficient indentation" do
      let(:source) do
        ["<%#",
         "    multiline",
         "    comment",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "  # multiline",
         "  # comment",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an indented multiline comment ERB tag" do
      let(:source) do
        ["<div>",
         "  <%#",
         "      multiline",
         "      comment",
         "  %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["     ",
         "    #",
         "    # multiline",
         "    # comment",
         "#   ",
         "      "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag followed by other ERB on the same line" do
      let(:source) do
        ["<%#",
         "  multiline",
         "  comment",
         "%><% if :cond %>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   ",
         "           ",
         "         ",
         "     if :cond;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag without leading whitespace" do
      let(:source) do
        ["<%#",
         "text",
         "more",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#ext",
         "#ore",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with tab indentation" do
      let(:source) do
        ["<%#",
         "\ttext",
         "\tmore",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#text",
         "#more",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline comment ERB tag with multibyte characters" do
      let(:source) do
        ["<%#",
         "日本語",
         "%>"].join("\n")
      end
      let(:expected) do
        ["  #",
         "#  本語",
         "  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with output tag containing multibyte characters" do
      let(:source) { '<%= "エラー" %>' }
      let(:expected) { '_ = "エラー";  ' }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Multibyte characters BEFORE ERB tag (regression test for byte offset bug)
    describe "with multibyte characters before output tag" do
      let(:source) { "日本語<%= x %>" }
      let(:expected) { "         _ = x;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with emoji characters before output tag" do
      let(:source) { "🎉🎉🎉<%= x %>" }
      let(:expected) { "            _ = x;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multibyte characters before execution tag" do
      let(:source) { "あいうえお<% code %>" }
      let(:expected) { "                  code;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end
  end
end
