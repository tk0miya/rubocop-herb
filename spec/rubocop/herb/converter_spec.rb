# frozen_string_literal: true

require "spec_helper"

require "prism"

RSpec.describe RuboCop::Herb::Converter do
  shared_examples "a Ruby code extractor for ERB" do
    describe "ruby_code" do
      it "matches the expected code, preserves source length and lines, and is valid Ruby" do
        expect(subject.ruby_code).to eq(expected)
        expect(subject.ruby_code.lines.map(&:length)).to eq(source.lines.map(&:length))

        # Skip for yield tests - yield is not valid Ruby outside of a method
        unless defined?(skip_valid_ruby_check) && skip_valid_ruby_check
          parse_result = Prism.parse(subject.ruby_code)
          expect(parse_result.errors).to be_empty
        end
      end
    end

    describe "hybrid_code" do
      it "matches the expected code and preserves source length" do
        expected_hybrid_code = defined?(expected_hybrid) ? expected_hybrid : expected

        expect(subject.hybrid_code).to eq(expected_hybrid_code)
        expect(subject.hybrid_code.length).to eq(source.length)
      end
    end

    describe "ruby_code and hybrid_code" do
      it "have the same length" do
        expect(subject.ruby_code.length).to eq(subject.hybrid_code.length)
      end
    end
  end

  describe "#convert" do
    subject { described_class.new.convert("test.html.erb", source) }

    # Basic ERB tags with HTML open/close tag rendering
    describe "with a content ERB tag" do
      let(:source) { "<div><%= user.name %></div>" }
      let(:expected) { "div; _ = user.name;  div;  " }
      let(:expected_hybrid) { "<div>_ = user.name;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a raw output ERB tag" do
      let(:source) { "<div><%== user.name %></div>" }
      let(:expected) { "div;  _ = user.name;  div;  " }
      let(:expected_hybrid) { "<div> _ = user.name;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a raw output ERB tag following multi-byte characters" do
      let(:source) { "<div>表示件数<%== @count %></div>" }
      let(:expected) { "div; _a;  _ = @count;  div;  " }
      let(:expected_hybrid) { "<div>_a;  _ = @count;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an empty output ERB tag" do
      let(:source) { "<div><%= %></div>" }
      let(:expected) { "div;    ;  div;  " }
      let(:expected_hybrid) { "<div>   ;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag" do
      let(:source) { "<div><%# user.name %>\n</div>" }
      let(:expected) { "div;   # user.name   \ndiv;  " }
      let(:expected_hybrid) { "<div>  # user.name   \n</div>" }

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
        ["_a;             ",
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
      let(:expected) { "div;      _ = foo;      div;  " }
      let(:expected_hybrid) { "<div>     _ = foo;      </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an HTML comment containing multi-byte characters" do
      let(:source) { "<body><!-- あいう --><%= render 'foo' %></body>" }
      # The comment "<!-- あいう -->" is 14 characters, rendered as "_a;" at start + spaces
      # Comments with multi-byte chars are not restored to preserve character count
      # Source: 44 chars -> Ruby: 44 chars
      let(:expected) { "body; _a;         _ = render 'foo';  body;  " }
      let(:expected_hybrid) { "<body>_a;         _ = render 'foo';  </body>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with text node shorter than 4 characters" do
      let(:source) { "<div>abc<%= x %></div>" }
      let(:expected) { "div;    _ = x;  div;  " }
      let(:expected_hybrid) { "<div>   _ = x;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with text node of 4 characters" do
      let(:source) { "<div>abcd<%= x %></div>" }
      let(:expected) { "div; _a; _ = x;  div;  " }
      let(:expected_hybrid) { "<div>abcd_ = x;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # "_a" is rendered without ";" because the newline terminates the statement
    describe "with text node of 2 characters followed by a newline" do
      let(:source) { "<%= x %>ab\n<%= y %>" }
      let(:expected) { "_ = x;  _a\n_ = y;  " }
      let(:expected_hybrid) { "_ = x;  ab\n_ = y;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # The marker is placed at the line where it fits not to overwrite the newline
    describe "with text node spanning multiple lines" do
      let(:source) { "<div>a\nbcde<%= x %></div>" }
      let(:expected) { "div;  \n_a; _ = x;  div;  " }
      let(:expected_hybrid) { "<div>a\nbcde_ = x;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with lone carriage returns" do
      let(:source) { "<div>\r<%= x %>\r</div>\n<%= y %>\n" }
      let(:expected) { "div; \r_ = x;  \rdiv;  \n_ = y;  \n" }
      let(:expected_hybrid) { "<div>\r_ = x;  \r</div>\n_ = y;  \n" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with text node containing multi-byte characters" do
      let(:source) { "<div>表示件数<%= @count %></div>" }
      # "表示件数" is 4 characters, bleached to 4 spaces with "_a;" marker (leaves 1 space)
      # Text nodes with multi-byte chars are not restored to preserve character count
      # Source: 28 chars -> Ruby: 28 chars
      let(:expected) { "div; _a; _ = @count;  div;  " }
      let(:expected_hybrid) { "<div>_a; _ = @count;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multi-byte characters in an HTML attribute and an ERB tag" do
      let(:source) { '<div title="あ"><%= "い" %></div>' }
      let(:expected) { 'div;           _ = "い";  div;  ' }
      let(:expected_hybrid) { '<div title="あ">_ = "い";  </div>' }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Escaped ERB tags (`<%%`) output the tag as text, so they are rendered like text nodes
    describe "with an escaped ERB tag in an element without ERB" do
      let(:source) { "<p><%% foo %></p>" }
      let(:expected) { "p;               " }
      let(:expected_hybrid) { "<p><%% foo %></p>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB tag followed by an ERB tag" do
      let(:source) { "<p><%% foo %><%= x %></p>" }
      let(:expected) { "p; _a;       _ = x;  p;  " }
      let(:expected_hybrid) { "<p><%% foo %>_ = x;  </p>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped output ERB tag" do
      let(:source) { "<%%= foo %><%= x %>" }
      let(:expected) { "_a;        _ = x;  " }
      let(:expected_hybrid) { "<%%= foo %>_ = x;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB tag closed with an escaped closing" do
      let(:source) { "<%% foo %%><%= x %>" }
      let(:expected) { "_a;        _ = x;  " }
      let(:expected_hybrid) { "<%% foo %%>_ = x;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB comment tag" do
      let(:source) { "<%%# rubocop:disable Lint/Void %>\n<% 1 %>" }
      let(:expected) { "_a;                              \n   1;  " }
      let(:expected_hybrid) { "<%%# rubocop:disable Lint/Void %>\n   1;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB block containing an ERB tag" do
      let(:source) { "<%% items.each do |item| %><%= item %><%% end %>" }
      let(:expected) { "_a;                        _ = item;  _a;       " }
      let(:expected_hybrid) { "<%% items.each do |item| %>_ = item;  <%% end %>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB tag containing multi-byte characters" do
      let(:source) { "<p>あ<%% い %><%= x %></p>" }
      # The escaped ERB tag is not restored to preserve character count (like text nodes)
      let(:expected) { "p;  _a;     _ = x;  p;  " }
      let(:expected_hybrid) { "<p> _a;     _ = x;  </p>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an escaped ERB tag in an HTML attribute" do
      let(:source) { '<div class="<%% x %>" id="<%= y %>"></div>' }
      let(:expected) { "div;        _a;           _ = y;    div;  " }
      let(:expected_hybrid) { "div;        <%% x %>      _ = y;    </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with execution tag without output" do
      let(:source) { "<div><% @counter += 1 %></div>" }
      let(:expected) { "div;    @counter += 1;  div;  " }
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
      let(:expected) do
        ["div; ",
         "     if admin?;  ",
         "    _a;          ",
         "     end;  ",
         "div;  "].join("\n")
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

    describe "with unless-ERB tags" do
      let(:source) do
        ["<div>",
         "  <% unless logged_in? %>",
         "    Please log in",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["div; ",
         "     unless logged_in?;  ",
         "    _a;          ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     unless logged_in?;  ",
         "    Please log in",
         "     end;  ",
         "</div>"].join("\n")
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
        ["div; ",
         "     if admin?;  ",
         "    _a;  ",
         "     elsif moderator?;  ",
         "    _a;      ",
         "     else;  ",
         "    _a; ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     if admin?;  ",
         "    Admin",
         "     elsif moderator?;  ",
         "    Moderator",
         "     else;  ",
         "    User",
         "     end;  ",
         "</div>"].join("\n")
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
        ["div; ",
         "     case status;  ",
         "     when :active;  ",
         "    _a;   ",
         "     when :inactive;  ",
         "    _a;     ",
         "     else;  ",
         "    _a;    ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     case status;  ",
         "     when :active;  ",
         "    Active",
         "     when :inactive;  ",
         "    Inactive",
         "     else;  ",
         "    Unknown",
         "     end;  ",
         "</div>"].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an ERB tag continuing and closing a control flow" do
      let(:source) do
        ["<% if admin? %>",
         "  <%= name %>",
         "<% else; end %>"].join("\n")
      end
      let(:expected) do
        ["   if admin?;  ",
         "  _ = name;  ",
         "   else; end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an ERB tag holding a case and its first condition" do
      let(:source) do
        ["<% case status when :active %>",
         "  Active",
         "<% when :inactive %>",
         "  Inactive",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   case status when :active;  ",
         "  _a;   ",
         "   when :inactive;  ",
         "  _a;     ",
         "   end;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["   case status when :active;  ",
         "  Active",
         "   when :inactive;  ",
         "  Inactive",
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
      # Output tags inside HTML elements need _ = because closing tags follow
      let(:expected) do
        ["   if page.current?;  ",
         "  li; _ = content_tag :a, page;  li;  ",
         "   else;  ",
         "  li; _ = link_to page, url;  li;  ",
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
      let(:expected) do
        ["div; ",
         "     if campaign;  ",
         "    input;        _ = locale_class;      ",
         "     else;  ",
         "    input;              _ = locale_class;      ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     if campaign;  ",
         "    input;        _ = locale_class;      ",
         "     else;  ",
         "    input;              _ = locale_class;      ",
         "     end;  ",
         "</div>"].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with case-in-ERB tags (pattern matching)" do
      let(:source) do
        ["<div>",
         "  <% case value %>",
         "  <% in Integer => n %>",
         "    <%= n %>",
         "  <% in String %>",
         "    Text",
         "  <% else %>",
         "    Unknown",
         "  <% end %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["div; ",
         "     case value;  ",
         "     in Integer => n;  ",
         "    _ = n;  ",
         "     in String;  ",
         "    _a; ",
         "     else;  ",
         "    _a;    ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     case value;  ",
         "     in Integer => n;  ",
         "    _ = n;  ",
         "     in String;  ",
         "    Text",
         "     else;  ",
         "    Unknown",
         "     end;  ",
         "</div>"].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with case-in-ERB tags on single line" do
      let(:source) { "<% case value %><% in 1 %>one<% end %>" }
      let(:expected) { "   case value;     in 1;        end;  " }

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
         "    li; _ = user.name;  li;  ",
         "     end;  ",
         "ul;  "].join("\n")
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
         "    p; _ = i;  p;  ",
         "     end;  ",
         "div;  "].join("\n")
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

    describe "with for-ERB tags" do
      let(:source) do
        ["<ul>",
         "  <% for item in items %>",
         "    <li><%= item %></li>",
         "  <% end %>",
         "</ul>"].join("\n")
      end
      let(:expected) do
        ["ul; ",
         "     for item in items;  ",
         "    li; _ = item;  li;  ",
         "     end;  ",
         "ul;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<ul>",
         "     for item in items;  ",
         "    <li>_ = item;  </li>",
         "     end;  ",
         "</ul>"].join("\n")
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
        ["div; ",
         "     while condition;  ",
         "    p;               ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     while condition;  ",
         "    <p>Processing</p>",
         "     end;  ",
         "</div>"].join("\n")
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
        ["div; ",
         "     until done;  ",
         "    p;            ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     until done;  ",
         "    <p>Waiting</p>",
         "     end;  ",
         "</div>"].join("\n")
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
        ["div; ",
         "     begin;  ",
         "    _ = risky_operation;  ",
         "     rescue StandardError => e;  ",
         "    _ = e.message;  ",
         "     ensure;  ",
         "       cleanup;  ",
         "     end;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["<div>",
         "     begin;  ",
         "    _ = risky_operation;  ",
         "     rescue StandardError => e;  ",
         "    _ = e.message;  ",
         "     ensure;  ",
         "       cleanup;  ",
         "     end;  ",
         "</div>"].join("\n")
      end

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
        ["div; ",
         "     if show_list?;  ",
         "    ul; ",
         "         items.each do |item|;  ",
         "        li; _ = item.name;  li;  ",
         "         end;  ",
         "    ul;  ",
         "     end;  ",
         "div;  "].join("\n")
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
         "  _ = value1;  ",
         "   else;  ",
         "  _ = value2;  ",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with multiple content tags on same line" do
      let(:source) { "<p><%= first %> and <%= second %></p>" }
      let(:expected) { "p; _ = first;   _a; _ = second;  p;  " }
      let(:expected_hybrid) { "<p>_ = first;   and _ = second;  </p>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with raw output tag (-%>)" do
      let(:source) { "<div><%= value -%></div>" }
      let(:expected) { "div; _ = value;   div;  " }
      let(:expected_hybrid) { "<div>_ = value;   </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline ERB tag whose tag closing is on its own line" do
      let(:source) { "<%\n  foo\n%>\n<%= bar %>" }
      let(:expected) { "  \n  foo\n  \n_ = bar;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a multiline ERB tag whose code has trailing whitespace before the tag closing" do
      let(:source) { "<%\n  foo  \n%>" }
      let(:expected) { "  \n  foo  \n  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Ruby comments at the end of the code in ERB tags
    describe "with a trailing Ruby comment in an ERB tag" do
      let(:source) { "<% x = 1 # comment %>" }
      let(:expected) { "   x = 1 # comment   " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a trailing Ruby comment in an ERB tag followed by other ERB on the same line" do
      let(:source) { "<%= x # comment %><%= y %>" }
      let(:expected) { "_ = x;            _ = y;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a trailing Ruby comment in a control flow ERB tag followed by other ERB on the same line" do
      let(:source) { "<% if x # comment %><%= y %><% end %>" }
      let(:expected) { "   if x;            _ = y;     end;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a trailing Ruby comment in an ERB tag followed by HTML on the same line" do
      let(:source) { "<% x = 1 # comment %><div></div>" }
      let(:expected) { "   x = 1;            div;       " }
      let(:expected_hybrid) { "   x = 1;            <div></div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a trailing Ruby comment in an ERB tag followed by a newline" do
      let(:source) do
        ["<% x = 1 # comment",
         "%><%= y %>"].join("\n")
      end
      let(:expected) do
        ["   x = 1 # comment",
         "  _ = y;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a hash sign in a string in an ERB tag followed by other ERB on the same line" do
      let(:source) { '<%= "a # b" %><%= y %>' }
      let(:expected) { '_ = "a # b";  _ = y;  ' }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a trailing Ruby comment with multi-byte characters in an ERB tag followed by other ERB" do
      let(:source) { '<%= "あ" # 日本語 %><%= y %>' }
      let(:expected) { '_ = "あ";        _ = y;  ' }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Comment ERB tags
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

    describe "with a comment ERB tag followed by HTML on the same line" do
      let(:source) { "<%# comment %><p>x</p>" }
      let(:expected) { "              p;      " }
      let(:expected_hybrid) { "              <p>x</p>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag with multi-byte characters followed by HTML on the same line" do
      # Shorter HTML than the difference between bytes and characters fails if byte positions are used as characters
      let(:source) { "<%# 日本語 %><br>" }
      let(:expected) { "          br; " }
      let(:expected_hybrid) { "          <br>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag followed by another comment ERB tag only on the same line" do
      let(:source) { "<%# a %><%# b %>" }
      let(:expected) { "  # a     # b   " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with a comment ERB tag followed by a multiline comment ERB tag on the same line" do
      let(:source) do
        ["<%# a %><%# b",
         "c %>"].join("\n")
      end
      let(:expected) do
        ["  # a     # b",
         "#   "].join("\n")
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
        ["div; ",
         "    #",
         "    # multiline",
         "    # comment",
         "#   ",
         "div;  "].join("\n")
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

    describe "with an indented multiline comment ERB tag followed by other ERB on the same line" do
      let(:source) do
        ["        <%# multi",
         "x %><%= :a %>"].join("\n")
      end
      let(:expected) do
        ["                 ",
         "    _ = :a;  "].join("\n")
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
      # Rendered to: "_a;  " (5 chars) + "   code;  " (10 chars) = 15 chars
      let(:expected) { "_a;     code;  " }

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
        ["html; ",
         "  _ = form_with do;  ",
         "     end;  ",
         "html; "].join("\n")
      end
      let(:expected_hybrid) do
        ["<html>",
         "  _ = form_with do;  ",
         "     end;  ",
         "<html>"].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # HTML tags
    describe "with open tag with attributes" do
      let(:source) { "<div class=\"foo\" id=\"bar\"><%= x %></div>" }
      let(:expected) { "div;                      _ = x;  div;  " }
      let(:expected_hybrid) { "<div class=\"foo\" id=\"bar\">_ = x;  </div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # HTML tags without ERB nodes should render tag name only and skip processing children
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
      let(:expected) { "div; _ = x;  p;         div;  " }
      let(:expected_hybrid) { "<div>_ = x;  <p>text</p></div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with nested inline elements" do
      let(:source) { '<p><code id="x"><%= y %></code></p>' }
      let(:expected) { "p; code;        _ = y;  code;  p;  " }
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
      let(:source) { '<div class="a"><%= yield %></div>' }
      let(:expected) { "div;           _ = yield;  div;  " }
      let(:expected_hybrid) { '<div class="a">_ = yield;  </div>' }
      let(:skip_valid_ruby_check) { true }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with yield ERB tag with conditional inside HTML element" do
      let(:source) { '<div class="form-body"><%= yield if block_given? %></div>' }
      let(:expected) { "div;                   _ = yield if block_given?;  div;  " }
      let(:expected_hybrid) { '<div class="form-body">_ = yield if block_given?;  </div>' }
      let(:skip_valid_ruby_check) { true }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with if-else containing HTML elements with attributes and ERB" do
      let(:source) do
        ["<% if condition %>",
         '  <div class="foo"><%= @name %></div>',
         "<% else %>",
         '  <div class="bar"><%= @other %></div>',
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   if condition;  ",
         "  div;             _ = @name;  div;  ",
         "   else;  ",
         "  div;             _ = @other;  div;  ",
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

    describe "with open tag containing ERB in attributes" do
      let(:source) { '<th class="<%= class_name %>"><%= content %></th>' }
      let(:expected) { "th;        _ = class_name;    _ = content;  th;  " }
      # Open tag is NOT restored because it contains ERB (would cause Layout/SpaceAroundOperators false positive)
      let(:expected_hybrid) { "th;        _ = class_name;    _ = content;  </th>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with open tag whose tag name is followed by a newline" do
      let(:source) { "<div\n  class=\"<%= x %>\">\n  <%= y %>\n</div>" }
      let(:expected) { "div;\n         _ = x;    \n  _ = y;  \ndiv;  " }
      let(:expected_hybrid) { "div;\n         _ = x;    \n  _ = y;  \n</div>" }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # Void elements (no close tag) render only the open tag
    describe "with void element containing ERB in attributes" do
      let(:source) { '<meta content="<%= x %>">' }
      let(:expected) { "meta;          _ = x;    " }
      let(:expected_hybrid) { "meta;          _ = x;    " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    # HTML tags not wrapped by an element
    describe "with an open tag without the close tag" do
      let(:source) { "<div class=\"a\">\n  <%= x %>" }
      let(:expected) { "div;           \n  _ = x;  " }
      let(:expected_hybrid) { "<div class=\"a\">\n  _ = x;  " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with an open tag containing ERB without the close tag" do
      let(:source) { "<b <%= x %>>" }
      let(:expected) { "b; _ = x;   " }

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with open tags in the branches of a conditional" do
      let(:source) do
        ["<% if a %>",
         "  <div class=\"a\">",
         "<% else %>",
         "  <div class=\"b\">",
         "<% end %>",
         "  <%= x %>",
         "</div>"].join("\n")
      end
      let(:expected) do
        ["   if a;  ",
         "  div;           ",
         "   else;  ",
         "  div;           ",
         "   end;  ",
         "  _ = x;  ",
         "div;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["   if a;  ",
         "  <div class=\"a\">",
         "   else;  ",
         "  <div class=\"b\">",
         "   end;  ",
         "  _ = x;  ",
         "</div>"].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end

    describe "with open and close tags in separate conditionals" do
      let(:source) do
        ["<% if a %>",
         "  <a href=\"/\">",
         "<% end %>",
         "link",
         "<% if a %>",
         "  </a>",
         "<% end %>"].join("\n")
      end
      let(:expected) do
        ["   if a;  ",
         "  a;          ",
         "   end;  ",
         "_a; ",
         "   if a;  ",
         "  a;  ",
         "   end;  "].join("\n")
      end
      let(:expected_hybrid) do
        ["   if a;  ",
         "  <a href=\"/\">",
         "   end;  ",
         "link",
         "   if a;  ",
         "  </a>",
         "   end;  "].join("\n")
      end

      it_behaves_like "a Ruby code extractor for ERB"
    end
  end
end
