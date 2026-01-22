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

    it "preserves byte length in ruby_code" do
      expect(subject.ruby_code.bytesize).to eq(source.bytesize)
    end

    it "preserves byte length in hybrid_code" do
      expect(subject.hybrid_code.bytesize).to eq(source.bytesize)
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
        # Control flow returns value, so last statement doesn't need _ =
        let(:expected) { "   if user;      user.name;     end;  " }

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
        # Control flow returns value, so last statements don't need _ =
        let(:expected) do
          ["   if condition;  ",
           "      value1;  ",
           "   else;  ",
           "      value2;  ",
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
        # Control flow returns value, so last statements (inside HTML) don't need _ =
        let(:expected) do
          ["   if page.current?;  ",
           "          content_tag :a, page;       ",
           "   else;  ",
           "          link_to page, url;       ",
           "   end;  "].join("\n")
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
          ["_1;             ",
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
        # The comment "<!-- あいう -->" is 20 bytes, rendered as "_1;" at start
        # Comments with multi-byte chars are not restored to preserve character count
        # Close tag uses counter 1 because comment already used counter 0
        let(:expected) { "body; _1;               _ = render 'foo';  body2; " }
        let(:expected_hybrid) { "<body>_1;               _ = render 'foo';  </body>" }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with text node containing multi-byte characters" do
        let(:source) { "<div>表示件数<%= @count %></div>" }
        # "表示件数" is 4 characters, 12 bytes - bleached to 12 spaces with "_1;" marker
        # Text nodes with multi-byte chars are not restored to preserve character count
        # Close tag uses counter 1 because text node already used counter 0
        let(:expected) { "div; _1;         _ = @count;  div2; " }
        let(:expected_hybrid) { "<div>_1;         _ = @count;  </div>" }

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
        # Close tag uses counter 1 because text node already used counter 0
        let(:expected) do
          ["div; ",
           "     if admin?;  ",
           "    _1;          ",
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
        # Control flow returns value, so last statements (inside HTML) don't need _ =
        let(:expected) do
          ["   if page.current?;  ",
           "  li;     content_tag :a, page;  li1; ",
           "   else;  ",
           "  li;     link_to page, url;  li2; ",
           "   end;  "].join("\n")
        end
        let(:expected_hybrid) do
          ["   if page.current?;  ",
           "  <li>    content_tag :a, page;  </li>",
           "   else;  ",
           "  <li>    link_to page, url;  </li>",
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
        # Close tag uses counter 1 because text node already used counter 0
        let(:expected) { "p; _ = first;   _1; _ = second;  p2; " }
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
        let(:expected) { "div {                     _ = x;  }     " }
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
        let(:expected) { "div {          _ = yield;  }     " }
        let(:expected_hybrid) { '<div class="a">_ = yield;  </div>' }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with yield ERB tag with conditional inside HTML element" do
        let(:source) { '<div class="form-body"><%= yield if block_given? %></div>' }
        let(:expected) { "div {                  _ = yield if block_given?;  }     " }
        let(:expected_hybrid) { '<div class="form-body">_ = yield if block_given?;  </div>' }
        let(:skip_valid_ruby_check) { true }

        it_behaves_like "a Ruby code extractor for ERB"
      end

      describe "with open tag containing ERB in attributes" do
        let(:source) { '<th class="<%= class_name %>"><%= content %></th>' }
        let(:expected) { "th {       _ = class_name;    _ = content;  }    " }
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
           "    _1;               ",
           "     else;  ",
           "     br; ",
           "    _2;   ",
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
    end
  end
end
