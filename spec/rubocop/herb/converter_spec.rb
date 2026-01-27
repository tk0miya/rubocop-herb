# frozen_string_literal: true

require "spec_helper"

require "prism"

RSpec.describe RuboCop::Herb::Converter do
  shared_examples "a Ruby code extractor for ERB" do
    it "collects Ruby parts from ERB" do
      expect(subject.ruby_code).to eq(expected)
    end

    it "generates expected hybrid code" do
      expected_hybrid_code = defined?(expected_hybrid) ? expected_hybrid : expected
      expect(subject.hybrid_code).to eq(expected_hybrid_code)
    end

    it "preserves character length in ruby_code" do
      expect(subject.ruby_code.length).to eq(source.length)
    end

    it "preserves character length in hybrid_code" do
      expect(subject.hybrid_code.length).to eq(source.length)
    end

    it "preserves character length between ruby_code and hybrid_code" do
      expect(subject.ruby_code.length).to eq(subject.hybrid_code.length)
    end

    it "generates valid Ruby code" do
      # Skip for yield tests - yield is not valid Ruby outside of a method
      skip "yield is not valid Ruby outside of a method" if defined?(skip_valid_ruby_check) && skip_valid_ruby_check

      parse_result = Prism.parse(subject.ruby_code)
      expect(parse_result.errors).to be_empty
    end
  end

  describe "#convert" do
    context "when html_visualization is disabled (default)" do
      subject { described_class.new.convert("test.html.erb", source) }

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

      # HTML comments (rendered as spaces when html_visualization is disabled)
      describe "with an HTML comment tag" do
        let(:source) { "<div><!-- user.name --></div>" }
        let(:expected) { "                             " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment tag followed by ERB" do
        let(:source) do
          ["<!-- comment -->",
           "<% if :cond %>",
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["                ",
           "   if :cond;  ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment containing ERB" do
        let(:source) { "<!-- <%= foo %> -->" }
        let(:expected) { "     _ = foo;      " }

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
           "    _ = risky_operation;  ",
           "     rescue StandardError => e;  ",
           "    _ = e.message;  ",
           "     ensure;  ",
           "       cleanup;  ",
           "     end;  ",
           "      "].join("\n")
        end

        # All output tags get _ = prefix when html_visualization is disabled.
        # cleanup is execution tag, not output tag, so it never gets _ =.
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
        # All output tags get _ = prefix when html_visualization is disabled
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
        # All output tags get _ = prefix when html_visualization is disabled
        let(:expected) do
          ["   if condition;  ",
           "  _ = value1;  ",
           "   else;  ",
           "  _ = value2;  ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with if-else containing output tags wrapped in HTML elements" do
        let(:source) do
          ["<% if page.current? %>",
           "  <li><%= content_tag :a, page %></li>",
           "<% else %>",
           "  <li><%= link_to page, url %></li>",
           "<% end %>"].join("\n")
        end
        # All output tags get _ = prefix when html_visualization is disabled
        let(:expected) do
          ["   if page.current?;  ",
           "      _ = content_tag :a, page;       ",
           "   else;  ",
           "      _ = link_to page, url;       ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with if-else containing output tags in HTML attributes" do
        let(:source) do
          ["<div>",
           "  <% if campaign %>",
           '    <input class="<%= locale_class %>" />',
           "  <% else %>",
           '    <input class="trial <%= locale_class %>" />',
           "  <% end %>",
           "</div>"].join("\n")
        end
        # All output tags get _ = prefix when html_visualization is disabled
        let(:expected) do
          ["     ",
           "     if campaign;  ",
           "                  _ = locale_class;      ",
           "     else;  ",
           "                        _ = locale_class;      ",
           "     end;  ",
           "      "].join("\n")
        end

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

      # ERB yield tags
      # Note: yield is not valid Ruby outside of a method, so skip_valid_ruby_check is set
      describe "with yield ERB tag" do
        let(:source) { "<%= yield %>" }
        let(:expected) { "_ = yield;  " }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag with arguments" do
        let(:source) { "<%= yield :sidebar %>" }
        let(:expected) { "_ = yield :sidebar;  " }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag with conditional" do
        let(:source) { "<%= yield if block_given? %>" }
        let(:expected) { "_ = yield if block_given?;  " }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag inside HTML element" do
        let(:source) { "<div><%= yield %></div>" }
        let(:expected) { "     _ = yield;        " }
        let(:skip_valid_ruby_check) { true }

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

      describe "with other ERB followed by a comment ERB tag on the same line" do
        let(:source) do
          ["<% if :cond %><%# comment %>",
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["   if :cond;    # comment   ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with a comment ERB tag between two other ERB tags on the same line" do
        let(:source) { "<%= :a %><%# comment %><%= :b %>" }
        let(:expected) { "_ = :a;                _ = :b;  " }

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
        # Source: 10 chars (<%#\n日本語\n%>)
        # - Line 1: "<%#" (3) -> "  #" (3)
        # - Line 2: "日本語" (3) -> "#本語" (3) - 日 becomes #
        # - Line 3: "%>" (2) -> "  " (2) - bleached to spaces
        let(:expected) { "  #\n#本語\n  " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with output tag containing multibyte characters" do
        let(:source) { '<%= "エラー" %>' }
        let(:expected) { '_ = "エラー";  ' }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Multibyte characters BEFORE ERB tag (regression test for character offset bug)
      # These tests verify that character positions are used correctly, not byte positions
      describe "with multibyte characters before output tag" do
        let(:source) { "日本語<%= x %>" }
        # 日本語 (3 chars) + <%= x %> (8 chars) = 11 chars
        # Bleached to: 3 spaces + "_ = x;  " (8 chars) = 11 chars
        let(:expected) { "   _ = x;  " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with emoji characters before output tag" do
        let(:source) { "🎉🎉🎉<%= x %>" }
        # 🎉🎉🎉 (3 chars) + <%= x %> (8 chars) = 11 chars
        let(:expected) { "   _ = x;  " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with multibyte characters before execution tag" do
        let(:source) { "あいうえお<% code %>" }
        # あいうえお (5 chars) + <% code %> (10 chars) = 15 chars
        # Bleached to: 5 spaces + "   code;  " (10 chars) = 15 chars
        let(:expected) { "        code;  " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # HTML errors should not prevent Ruby extraction
      describe "with HTML errors (missing closing tags)" do
        let(:source) do
          ["<html>",
           "  <%= form_with do %>",
           "  <% end %>",
           "<html>"].join("\n")
        end
        let(:expected) do
          ["      ",
           "  _ = form_with do;  ",
           "     end;  ",
           "      "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end
    end

    context "when html_visualization is enabled" do
      subject { described_class.new(html_visualization: true).convert("test.html.erb", source) }

      # Basic ERB tags with HTML open/close tag rendering
      describe "with a content ERB tag" do
        let(:source) { "<div><%= user.name %></div>" }
        let(:expected) { "div; _ = user.name;  div1; " }
        let(:expected_hybrid) { "<div>_ = user.name;  </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with a comment ERB tag" do
        let(:source) { "<div><%# user.name %></div>" }
        let(:expected) { "div;   # user.name   div1; " }
        let(:expected_hybrid) { "<div>  # user.name   </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment tag" do
        let(:source) { "<div><!-- user.name --></div>" }
        let(:expected) { "div;                         " }
        let(:expected_hybrid) { "<div><!-- user.name --></div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment tag followed by ERB" do
        let(:source) do
          ["<!-- comment -->",
           "<% if :cond %>",
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["_b;             ",
           "   if :cond;  ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["<!-- comment -->",
           "   if :cond;  ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment containing ERB" do
        let(:source) { "<div><!-- <%= foo %> --></div>" }
        let(:expected) { "div;      _ = foo;      div1; " }
        let(:expected_hybrid) { "<div>     _ = foo;      </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with an HTML comment containing multi-byte characters" do
        let(:source) { "<body><!-- あいう --><%= render 'foo' %></body>" }
        # The comment "<!-- あいう -->" is 14 characters, rendered as "_b;" at start + spaces
        # Comments with multi-byte chars are not restored to preserve character count
        # Close tag uses counter 2 because comment already used counter 1
        # Source: 44 chars -> Ruby: 44 chars
        let(:expected) { "body; _b;         _ = render 'foo';  body2; " }
        let(:expected_hybrid) { "<body>_b;         _ = render 'foo';  </body>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with text node containing multi-byte characters" do
        let(:source) { "<div>表示件数<%= @count %></div>" }
        # "表示件数" is 4 characters, bleached to 4 spaces with "_b;" marker (leaves 1 space)
        # Text nodes with multi-byte chars are not restored to preserve character count
        # Close tag uses counter 2 because text node already used counter 1
        # Source: 28 chars -> Ruby: 28 chars
        let(:expected) { "div; _b; _ = @count;  div2; " }
        let(:expected_hybrid) { "<div>_b; _ = @count;  </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with execution tag without output" do
        let(:source) { "<div><% @counter += 1 %></div>" }
        let(:expected) { "div;    @counter += 1;  div1; " }
        let(:expected_hybrid) { "<div>   @counter += 1;  </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Control structures with HTML open/close tag rendering
      describe "with if-ERB tags" do
        let(:source) do
          ["<div>",
           "  <% if admin? %>",
           "    Hello, Admin!",
           "  <% end %>",
           "</div>"].join("\n")
        end
        # Close tag uses counter 2 because text node already used counter 1
        let(:expected) do
          ["div; ",
           "     if admin?;  ",
           "    _b;          ",
           "     end;  ",
           "div2; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<div>",
           "     if admin?;  ",
           "    Hello, Admin!",
           "     end;  ",
           "</div>"].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with if-else containing output tags wrapped in HTML elements" do
        let(:source) do
          ["<% if page.current? %>",
           "  <li><%= content_tag :a, page %></li>",
           "<% else %>",
           "  <li><%= link_to page, url %></li>",
           "<% end %>"].join("\n")
        end
        # Output tags inside HTML elements need _ = because closing tags follow
        let(:expected) do
          ["   if page.current?;  ",
           "  li; _ = content_tag :a, page;  li1; ",
           "   else;  ",
           "  li; _ = link_to page, url;  li2; ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["   if page.current?;  ",
           "  <li>_ = content_tag :a, page;  </li>",
           "   else;  ",
           "  <li>_ = link_to page, url;  </li>",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Loops with HTML open/close tag rendering
      describe "with block-ERB tags (each)" do
        let(:source) do
          ["<ul>",
           "  <% users.each do |user| %>",
           "    <li><%= user.name %></li>",
           "  <% end %>",
           "</ul>"].join("\n")
        end
        let(:expected) do
          ["ul; ",
           "     users.each do |user|;  ",
           "    li; _ = user.name;  li1; ",
           "     end;  ",
           "ul2; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<ul>",
           "     users.each do |user|;  ",
           "    <li>_ = user.name;  </li>",
           "     end;  ",
           "</ul>"].join("\n")
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
          ["div; ",
           "     3.times do |i|;  ",
           "    p; _ = i;  p1; ",
           "     end;  ",
           "div2; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<div>",
           "     3.times do |i|;  ",
           "    <p>_ = i;  </p>",
           "     end;  ",
           "</div>"].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

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
          ["div; ",
           "     if show_list?;  ",
           "    ul; ",
           "         items.each do |item|;  ",
           "        li; _ = item.name;  li1; ",
           "         end;  ",
           "    ul2; ",
           "     end;  ",
           "div3; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<div>",
           "     if show_list?;  ",
           "    <ul>",
           "         items.each do |item|;  ",
           "        <li>_ = item.name;  </li>",
           "         end;  ",
           "    </ul>",
           "     end;  ",
           "</div>"].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with multiple content tags on same line" do
        let(:source) { "<p><%= first %> and <%= second %></p>" }
        # Close tag uses counter 2 because text node already used counter 1
        let(:expected) { "p; _ = first;   _b; _ = second;  p2; " }
        let(:expected_hybrid) { "<p>_ = first;   and _ = second;  </p>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with raw output tag (-%>)" do
        let(:source) { "<div><%= value -%></div>" }
        let(:expected) { "div; _ = value;   div1; " }
        let(:expected_hybrid) { "<div>_ = value;   </div>" }

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
          ["div; ",
           "    #",
           "    # multiline",
           "    # comment",
           "#   ",
           "div1; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<div>",
           "    #",
           "    # multiline",
           "    # comment",
           "#   ",
           "</div>"].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with open tag with attributes" do
        let(:source) { "<div class=\"foo\" id=\"bar\"><%= x %></div>" }
        let(:expected) { "div {                     _ = x;  };    " }
        let(:expected_hybrid) { "<div class=\"foo\" id=\"bar\">_ = x;  </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # HTML tags without ERB nodes should render tag name only and skip processing children
      # Even with attributes (enough space for brace), use semicolon notation to avoid syntax errors
      describe "with HTML tag without ERB nodes" do
        let(:source) { "<div>text</div>" }
        let(:expected) { "div;           " }
        let(:expected_hybrid) { "<div>text</div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with HTML tag with attributes but without ERB nodes" do
        let(:source) { '<span class="admin">Admin</span>' }
        let(:expected) { "span;                           " }
        let(:expected_hybrid) { '<span class="admin">Admin</span>' }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with nested HTML tags without ERB nodes" do
        let(:source) { "<div><p>text</p></div>" }
        let(:expected) { "div;                  " }
        let(:expected_hybrid) { "<div><p>text</p></div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with parent tag containing ERB but child tag without ERB" do
        let(:source) { "<div><%= x %><p>text</p></div>" }
        let(:expected) { "div; _ = x;  p;         div1; " }
        let(:expected_hybrid) { "<div>_ = x;  <p>text</p></div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Nested inline elements where child uses brace notation but parent doesn't
      # The closing brace needs semicolon before parent's closing tag identifier
      describe "with nested inline elements where child has brace notation" do
        let(:source) { '<p><code id="x"><%= y %></code></p>' }
        let(:expected) { "p; code {       _ = y;  };     p1; " }
        let(:expected_hybrid) { "<p><code id=\"x\">_ = y;  </code></p>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with if-else containing HTML tags with attributes but without ERB" do
        let(:source) do
          ["<% if admin? %>",
           "  <span class=\"admin\">Admin</span>",
           "<% else %>",
           "  <span class=\"user\">User</span>",
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["   if admin?;  ",
           "  span;                           ",
           "   else;  ",
           "  span;                         ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["   if admin?;  ",
           "  <span class=\"admin\">Admin</span>",
           "   else;  ",
           "  <span class=\"user\">User</span>",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # ERB yield tags with HTML visualization
      # Note: yield is not valid Ruby outside of a method, so skip_valid_ruby_check is set
      describe "with yield ERB tag" do
        let(:source) { "<%= yield %>" }
        let(:expected) { "_ = yield;  " }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag with arguments" do
        let(:source) { "<%= yield :sidebar %>" }
        let(:expected) { "_ = yield :sidebar;  " }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag inside HTML element with brace notation" do
        let(:source) { '<div class="a"><%= yield %></div>' }
        let(:expected) { "div {          _ = yield;  };    " }
        let(:expected_hybrid) { '<div class="a">_ = yield;  </div>' }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag with conditional inside HTML element" do
        let(:source) { '<div class="form-body"><%= yield if block_given? %></div>' }
        let(:expected) { "div {                  _ = yield if block_given?;  };    " }
        let(:expected_hybrid) { '<div class="form-body">_ = yield if block_given?;  </div>' }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # HTML block with brace notation inside if-else should not be treated as tail expression
      # because HTML blocks don't return meaningful values
      describe "with if-else containing HTML block with brace notation" do
        let(:source) do
          ["<% if condition %>",
           '  <div class="foo"><%= @name %></div>',
           "<% else %>",
           '  <div class="bar"><%= @other %></div>',
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["   if condition;  ",
           "  div {            _ = @name;  };    ",
           "   else;  ",
           "  div {            _ = @other;  };    ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["   if condition;  ",
           '  <div class="foo">_ = @name;  </div>',
           "   else;  ",
           '  <div class="bar">_ = @other;  </div>',
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # When ERB nodes follow HTML blocks, those trailing ERB nodes should be tail expressions
      describe "with if-else containing HTML block followed by ERB" do
        let(:source) do
          ["<% if condition %>",
           '  <div class="foo"><%= @name %></div>',
           "  <%= @extra %>",
           "<% else %>",
           '  <div class="bar"><%= @other %></div>',
           "  <%= @extra2 %>",
           "<% end %>"].join("\n")
        end
        let(:expected) do
          ["   if condition;  ",
           "  div {            _ = @name;  };    ",
           "      @extra;  ",
           "   else;  ",
           "  div {            _ = @other;  };    ",
           "      @extra2;  ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["   if condition;  ",
           '  <div class="foo">_ = @name;  </div>',
           "      @extra;  ",
           "   else;  ",
           '  <div class="bar">_ = @other;  </div>',
           "      @extra2;  ",
           "   end;  "].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with open tag containing ERB in attributes" do
        let(:source) { '<th class="<%= class_name %>"><%= content %></th>' }
        let(:expected) { "th {       _ = class_name;    _ = content;  };   " }
        # Open tag is NOT restored because it contains ERB (would cause Layout/SpaceAroundOperators false positive)
        let(:expected_hybrid) { "th {       _ = class_name;    _ = content;  </th>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Void elements (no close tag) should use semicolon notation, not brace notation
      # Even with enough space for braces, using braces would cause Lint/Syntax error
      # because there's no close tag to render the closing brace
      describe "with void element containing ERB in attributes" do
        let(:source) { '<meta content="<%= x %>">' }
        let(:expected) { "meta;          _ = x;    " }
        let(:expected_hybrid) { "meta;          _ = x;    " }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Each HTML content gets unique counter to avoid Style/IdenticalConditionalBranches false positive
      describe "with if-else containing different HTML content in each branch" do
        let(:source) do
          ["<span>",
           "  <% if total_count.zero? %>",
           "    <!-- do noting -->",
           "  <% else %>",
           "    1<br>",
           "    &nbsp;",
           "  <% end %>",
           "</span>"].join("\n")
        end
        let(:expected) do
          ["span; ",
           "     if total_count.zero?;  ",
           "    _b;               ",
           "     else;  ",
           "     br; ",
           "    _c;   ",
           "     end;  ",
           "span3; "].join("\n")
        end
        let(:expected_hybrid) do
          ["<span>",
           "     if total_count.zero?;  ",
           "    <!-- do noting -->",
           "     else;  ",
           "     <br>",
           "    &nbsp;",
           "     end;  ",
           "</span>"].join("\n")
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Static text in attribute values should get markers when mixed with ERB
      # to avoid Lint/DuplicateBranch false positives
      describe "with if-else containing attribute values with different static text" do
        let(:source) do
          '<% if true %><div class="<%= "hello" %>"></div><% else %><div class="<%= "hello" %> world"></div><% end %>'
        end
        # The " world" gets a _b; marker to distinguish the branches
        let(:expected) do
          '   if true;  div {       _ = "hello";    };       else;  div {       _ = "hello";  _b;     };       end;  '
        end
        let(:expected_hybrid) do
          '   if true;  div {       _ = "hello";    </div>   else;  div {       _ = "hello";  _b;     </div>   end;  '
        end

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Conditional attributes (HTMLAttributeNode in ERB statements) should get markers
      # to avoid Lint/DuplicateBranch false positives
      describe "with if-else containing conditional attributes" do
        let(:source) { '<div <% if true %>class="foo"<% else %>class="bar"<% end %>></div>' }
        # Each attribute gets a marker (_b, _c) to distinguish the branches
        let(:expected) { "div {   if true;  _b;           else;  _c;           end;   };    " }
        let(:expected_hybrid) { "div {   if true;  _b;           else;  _c;           end;   </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      # Attribute value with multiple static text segments around ERB
      describe "with attribute value containing ERB surrounded by static text" do
        let(:source) { '<div class="prefix <%= middle %> suffix"></div>' }
        # Counter starts at 1, so first marker is _b, second is _c
        let(:expected) { "div {       _b;    _ = middle;  _c;      };    " }
        let(:expected_hybrid) { "div {       _b;    _ = middle;  _c;      </div>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end
    end
  end
end
