# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Lint and autocorrect with RuboCop", type: :feature do
  include_context "with the whole RuboCop"

  context "when analyzing a rubocop directive in a trailing Ruby comment of an ERB tag" do
    it "applies the directive" do
      expect_no_offenses(<<~ERB)
        <% x = 1 # rubocop:disable Lint/UselessAssignment %>
      ERB
    end
  end

  context "when analyzing an ERB tag following an ERB tag with a trailing Ruby comment on the same line" do
    it "checks the following ERB tag" do
      expect_offense(<<~ERB)
        <%= x # comment %><%= y==1 %>
                               ^^ Layout/SpaceAroundOperators: Surrounding space missing for operator `==`.
      ERB

      expect_correction(<<~ERB)
        <%= x # comment %><%= y == 1 %>
      ERB
    end
  end

  context "when analyzing a block whose body is an ERB comment followed by HTML on the same line" do
    it "triggers Lint/UnusedBlockArgument as for the body without the comment" do
      expect_offense(<<~ERB)
        <% items.each do |item| %>
                          ^^^^ Lint/UnusedBlockArgument: Unused block argument - `item`. You can omit the argument if you don't care about it.
          <%# comment %><li>x</li>
        <% end %>
      ERB

      expect_correction(<<~ERB)
        <% items.each do |_item| %>
          <%# comment %><li>x</li>
        <% end %>
      ERB
    end
  end

  context "when analyzing if-else-end with output tags" do
    it "does not trigger Style/ConditionalAssignment" do
      expect_no_offenses(<<~ERB)
        <% if condition %>
          <%= value1 %>
        <% else %>
          <%= value2 %>
        <% end %>
      ERB
    end
  end

  context "when analyzing if-else-end with output tags wrapped in HTML elements" do
    it "does not trigger Style/ConditionalAssignment" do
      expect_no_offenses(<<~ERB)
        <% if page.current? %>
          <li class="active"><%= content_tag :a, page %></li>
        <% else %>
          <li><%= link_to page, url %></li>
        <% end %>
      ERB
    end
  end

  context "when analyzing raw output tags" do
    it "does not trigger Lint/Void" do
      expect_no_offenses(<<~ERB)
        <div><%== @html %></div>
      ERB
    end
  end

  context "when analyzing if block with output tag followed by non-output tag" do
    it "does not trigger Lint/Void" do
      expect_no_offenses(<<~ERB)
        <% if foo? %>
          <%= 'close' if bar? %>
          <% :foo %>
        <% end %>
      ERB
    end
  end

  context "when analyzing each block with output tags with HTML close tags" do
    it "does not trigger Lint/Void" do
      expect_no_offenses(<<~ERB)
        <ul>
          <% items.each do |item| %>
            <li><%= item %></li>
          <% end %>
        </ul>
      ERB
    end
  end

  context "when analyzing if block with output tag followed by another output tag" do
    it "does not trigger Lint/Void" do
      expect_no_offenses(<<~ERB)
        <div>
          <% if @error %>
            <div><%= @error %></div>
          <% end %>
          <div><%= render 'index' %></div>
        </div>
      ERB
    end
  end

  context "when analyzing ERB with multi-byte characters in comments" do
    it "does not trigger Layout/SpaceBeforeFirstArg" do
      expect_no_offenses(<<~ERB)
        <div class="form">
          <%# 日本語コメント %>
          <div class="inner">
            <input value="<%= foo.bar %>" />
            <label><%= baz(qux: @value) %></label>
          </div>
        </div>
      ERB
    end
  end

  context "when analyzing conditional branches containing only HTML" do
    it "does not trigger Lint/EmptyConditionalBody" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <p>a</p>
        <% elsif b %>
          <!-- b -->
        <% end %>
        <% unless c %>
          c
        <% end %>
        <% if d %>
          <a href="/">
        <% end %>
        d
        <% if d %>
          </a>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches without any content" do
    it "triggers Lint/EmptyConditionalBody" do
      expect_offense(<<~ERB)
        <% if a %>
           ^^^^^^^ Lint/EmptyConditionalBody: Avoid `if` branches without a body.
        <% elsif b %>
          <%= b %>
        <% end %>
        <% unless c %>
           ^^^^^^^^^^^ Lint/EmptyConditionalBody: Avoid `unless` branches without a body.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing an empty if branch followed by an elsif branch containing only HTML" do
    it "triggers Lint/EmptyConditionalBody only for the empty if branch" do
      expect_offense(<<~ERB)
        <% if a %>
           ^^^^^^^ Lint/EmptyConditionalBody: Avoid `if` branches without a body.
        <% elsif b %>
          <p>b</p>
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing rescue and ensure clauses containing only HTML" do
    it "does not trigger Lint/SuppressedException and Lint/EmptyEnsure" do
      expect_no_offenses(<<~ERB)
        <% begin %>
          <p>x</p>
        <% rescue StandardError %>
          e
        <% ensure %>
          d
        <% end %>
      ERB
    end
  end

  context "when analyzing rescue and ensure clauses without any content" do
    it "triggers Lint/SuppressedException and Lint/EmptyEnsure" do
      expect_offense(<<~ERB)
        <% begin %>
          <p>x</p>
        <% rescue StandardError %>
           ^^^^^^^^^^^^^^^^^^^^^ Lint/SuppressedException: Do not suppress exceptions.
        <% ensure %>
           ^^^^^^ Lint/EmptyEnsure: Empty `ensure` block detected.
        <% end %>
      ERB

      expect_correction(<<~ERB)
        <% begin %>
          <p>x</p>
        <% rescue StandardError %>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditionals written across ERB tags on a single line" do
    it "does not trigger Style/OneLineConditional" do
      expect_offense(<<~ERB)
        <% if a %>foo<% elsif b %><% end %>
        <% if a %><%= x %><% else %><%= y %><% end %>
        <% unless a %><%= x %><% else %><%= y %><% end %>
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Style/UnlessElse: Do not use `unless` with `else`. Rewrite these with the positive case first.
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing when tags written across ERB tags" do
    it "triggers Style/WhenThen only for the code in a single ERB tag" do
      expect_offense(<<~ERB)
        <% case a %><% when 1 %><%= x %><% else %><%= y %><% end %>
        <% case a when 1; b end %>
                        ^ Style/WhenThen: Do not use `when 1;`. Use `when 1 then` instead.
      ERB

      expect_correction(<<~ERB)
        <% case a %><% when 1 %><%= x %><% else %><%= y %><% end %>
        <% case a when 1 then b end %>
      ERB
    end
  end

  context "when analyzing in tags written across ERB tags" do
    it "triggers Style/InPatternThen only for the code in a single ERB tag" do
      expect_offense(<<~ERB)
        <% case a %><% in 1 %><%= x %><% else %><%= y %><% end %>
        <% case a
           in 1; b
               ^ Style/InPatternThen: Do not use `in 1;`. Use `in 1 then` instead.
           end %>
      ERB

      expect_correction(<<~ERB)
        <% case a %><% in 1 %><%= x %><% else %><%= y %><% end %>
        <% case a
           in 1 then b
           end %>
      ERB
    end
  end

  context "when analyzing else tags written across ERB tags" do
    it "triggers Lint/ElseLayout only for the code in a single ERB tag" do
      expect_offense(<<~ERB)
        <% if a %><%= x %>
        <% else %><%= y %><% end %>
        <% if a
             b
           else c
                ^ Lint/ElseLayout: Odd `else` layout detected. Did you mean to use `elsif`?
           end %>
      ERB

      expect_correction(<<~ERB)
        <% if a %><%= x %>
        <% else %><%= y %><% end %>
        <% if a
             b
           else
             c
           end %>
      ERB
    end
  end

  context "when analyzing a conditional written in a single ERB tag" do
    it "triggers Style/OneLineConditional" do
      expect_offense(<<~ERB)
        <% if a then b else c end %>
           ^^^^^^^^^^^^^^^^^^^^^^ Style/OneLineConditional: Favor the ternary operator (`?:`) over single-line `if/then/else/end` constructs.
      ERB

      expect_correction(<<~ERB)
        <% a ? b : c %>
      ERB
    end
  end

  context "when analyzing conditionals written across ERB tags and in a single ERB tag" do
    it "triggers Style/IfWithSemicolon and Style/IfUnlessModifier only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>a</p>
        <% elsif b %>
          <p>b</p>
        <% end %>
        <% unless c %>
          <%= c %>
        <% end %>
        <% if d; foo; end %>
           ^^ Style/IfUnlessModifier: Favor modifier `if` usage when having a single-line body. Another good alternative is the usage of control flow `&&`/`||`.
           ^^^^^^^^^^^^^^ Style/IfWithSemicolon: Do not use `if d;` - use a ternary operator instead.
      ERB

      expect_correction(<<~ERB)
        <% if a %>
          <p>a</p>
        <% elsif b %>
          <p>b</p>
        <% end %>
        <% unless c %>
          <%= c %>
        <% end %>
        <% foo if d %>
      ERB
    end
  end

  context "when analyzing case statements with output tags and a conditional assignment in a single ERB tag" do
    it "triggers Style/ConditionalAssignment only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <% case a %>
        <% when 1 %>
          <%= x %>
        <% else %>
          <%= y %>
        <% end %>
        <% case b %>
        <% in 1 %>
          <%= x %>
        <% in 2 %>
          <%= y %>
        <% end %>
        <% if c
           ^^^^ Style/ConditionalAssignment: Use the return of the conditional for variable assignment and comparison.
             @z = 1
           else
             @z = 2
           end %>
      ERB

      expect_correction(<<~ERB)
        <% case a %>
        <% when 1 %>
          <%= x %>
        <% else %>
          <%= y %>
        <% end %>
        <% case b %>
        <% in 1 %>
          <%= x %>
        <% in 2 %>
          <%= y %>
        <% end %>
        <% @z = if c
                  1
                else
                  2
                end %>
      ERB
    end
  end

  context "when analyzing multiple output tags" do
    it "does not trigger Lint/UnderscorePrefixedVariableName" do
      expect_no_offenses(<<~ERB)
        <%= content_for(:page_title) %>
        <% items.each do |item| %>
          <%= item %>
        <% end %>
      ERB
    end
  end

  context "when analyzing yield ERB tag inside HTML element" do
    it "does not trigger Lint/EmptyBlock" do
      expect_no_offenses(<<~ERB)
        <div class="portlet-body form">
          <div class="form-body"><%= yield if block_given? %></div>
        </div>
      ERB
    end
  end

  context "when analyzing output tag inside HTML attribute" do
    it "does not trigger Layout/SpaceAroundOperators" do
      expect_no_offenses(<<~ERB)
        <th class="<%= class_name %>"><%= content %></th>
      ERB
    end
  end

  context "when analyzing output tags without whitespace after their tag openings" do
    it "does not trigger Layout/SpaceAroundOperators" do
      expect_no_offenses(<<~ERB)
        <%=foo%>
        <%==bar%>
        <%=yield%>
        <%=form_with do |f|%>
          <%= f.text_field :name %>
        <% end %>
      ERB
    end
  end

  context "when analyzing block with text node inside" do
    it "does not trigger Style/NumberedParameters" do
      expect_no_offenses(<<~ERB)
        <%= items.each do %>hello<% end %>
      ERB
    end
  end

  context "when analyzing if-else with HTML elements with attributes" do
    it "does not trigger Style/ConditionalAssignment" do
      expect_no_offenses(<<~ERB)
        <% if condition %>
          <div class="foo"><%= @name %></div>
        <% else %>
          <div class="bar"><%= @other %></div>
        <% end %>
      ERB
    end
  end

  context "when analyzing local variable assigned in HTML element and used after it" do
    it "does not trigger Lint/UselessAssignment" do
      expect_no_offenses(<<~ERB)
        <div class="box">
          <% total = items.sum %>
        </div>
        <%= total %>
      ERB
    end
  end

  context "when analyzing if-else with HTML elements with attributes followed by ERB" do
    it "does not trigger Style/ConditionalAssignment" do
      expect_no_offenses(<<~ERB)
        <% if condition %>
          <div class="foo"><%= @name %></div>
          <%= @extra %>
        <% else %>
          <div class="bar"><%= @other %></div>
          <%= @extra2 %>
        <% end %>
      ERB
    end
  end

  context "when analyzing control flows whose branches output values followed by HTML" do
    it "does not trigger Lint/Void" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <%= x %>
        <% else %>
          <%= y %>
        <% end %>
        <% case b %>
        <% when 1 %>
          <%= x %>
        <% else %>
          <%= y %>
        <% end %>
        <% case c %>
        <% in 1 %>
          <%= x %>
        <% else %>
          <%= y %>
        <% end %>
        <% begin %>
          <%= x %>
        <% ensure %>
          <%= y %>
        <% end %>
        <p>z</p>
      ERB
    end
  end

  context "when analyzing conditionals whose branches output the condition" do
    it "triggers Style/RedundantCondition only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <% if a %>
          <p><%= a %></p>
        <% else %>
          <p><%= b %></p>
        <% end %>
        <% if c %>
          <%= c %>
        <% end %>
        <%= if d
            ^^^^ Style/RedundantCondition: Use double pipes `||` instead.
              d
            else
              e
            end %>
      ERB

      expect_correction(<<~ERB)
        <% if a %>
          <p><%= a %></p>
        <% else %>
          <p><%= b %></p>
        <% end %>
        <% if c %>
          <%= c %>
        <% end %>
        <%= d || e %>
      ERB
    end
  end

  context "when analyzing conditionals at the end of blocks" do
    it "triggers Style/Next only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <ul>
          <% items.each do |item| %>
            <% if item.visible? %>
              <li><%= item.a %></li>
              <li><%= item.b %></li>
              <li><%= item.c %></li>
            <% end %>
          <% end %>
        </ul>
        <% others.each do |other|
             if other.valid?
             ^^^^^^^^^^^^^^^ Style/Next: Use `next` to skip iteration.
               save(other)
               notify(other)
               log(other)
             end
           end %>
      ERB

      expect_correction(<<~ERB)
        <ul>
          <% items.each do |item| %>
            <% if item.visible? %>
              <li><%= item.a %></li>
              <li><%= item.b %></li>
              <li><%= item.c %></li>
            <% end %>
          <% end %>
        </ul>
        <% others.each do |other|
             next unless other.valid?

             save(other)
             notify(other)
             log(other)
           end %>
      ERB
    end
  end

  context "when analyzing blocks written across ERB tags" do
    it "triggers Style/BlockDelimiters only for the multi-line brace block" do
      expect_offense(<<~ERB)
        <p class="a"><%= x %></p>
        <% items.each do |item| %><b><%= item %></b><% end %>
        <%= form_with do |f| %><%= f.text_field :name %><% end %>
        <% others.each do |other| %>
          <%= other %>
        <% end %>
        <% foos.each { |foo| %>
                     ^ Style/BlockDelimiters: Avoid using `{...}` for multi-line blocks.
          <%= foo %>
        <% } %>
      ERB

      expect_correction(<<~ERB)
        <p class="a"><%= x %></p>
        <% items.each do |item| %><b><%= item %></b><% end %>
        <%= form_with do |f| %><%= f.text_field :name %><% end %>
        <% others.each do |other| %>
          <%= other %>
        <% end %>
        <% foos.each do |foo| %>
          <%= foo %>
        <% end %>
      ERB
    end
  end

  context "when analyzing a block with HTML content on a single line" do
    it "does not trigger Style/SingleLineDoEndBlock" do
      expect_no_offenses(<<~ERB)
        <%= link_to root_path do %><span>Home</span><% end %>
      ERB
    end
  end

  context "when analyzing a single-line block in a single ERB tag" do
    it "triggers Style/BlockDelimiters and Style/SingleLineDoEndBlock" do
      expect_offense(<<~ERB)
        <% items.each do |i| foo(i) end %>
                      ^^ Style/BlockDelimiters: Prefer `{...}` over `do...end` for single-line blocks.
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Style/SingleLineDoEndBlock: Prefer multiline `do`...`end` block.
      ERB

      expect_correction(<<~ERB)
        <% items.each do |i|
             foo(i)
           end %>
      ERB
    end
  end

  context "when analyzing conditionals and loops whose end tags follow HTML" do
    it "triggers Layout/EndAlignment only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>a</p><% end %>
        <% case b %>
        <% when 1 %>
          <p>b</p><% end %>
        <% while c %>
          <p>c</p>
          <p>c</p><% end %>
        <% @d = if d
                  1
                else
                  2
             end %>
             ^^^ Layout/EndAlignment: `end` at 13, 5 is not aligned with `if` at 9, 8.
      ERB

      expect_correction(<<~ERB)
        <% if a %>
          <p>a</p><% end %>
        <% case b %>
        <% when 1 %>
          <p>b</p><% end %>
        <% while c %>
          <p>c</p>
          <p>c</p><% end %>
        <% @d = if d
                  1
                else
                  2
                end %>
      ERB
    end
  end

  context "when analyzing else and elsif tags that follow the HTML structure" do
    it "triggers Layout/ElseAlignment only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <span><% if a %>
          <% foo %>
        <% elsif b %>
          <% bar %>
        <% else %>
          <% baz %>
        <% end %></span>
        <% @c = if c %>
          <% foo %>
        <% else %>
          <% bar %>
        <% end %>
        <%
          if d
            foo
           else
           ^^^^ Layout/ElseAlignment: Align `else` with `if`.
             bar
          end
        %>
      ERB

      expect_correction(<<~ERB)
        <span><% if a %>
          <% foo %>
        <% elsif b %>
          <% bar %>
        <% else %>
          <% baz %>
        <% end %></span>
        <% @c = if c %>
          <% foo %>
        <% else %>
          <% bar %>
        <% end %>
        <%
          if d
            foo
          else
            bar
          end
        %>
      ERB
    end
  end

  context "when analyzing blocks whose end tags follow the HTML structure" do
    it "triggers Layout/BlockAlignment only for the block in a single ERB tag" do
      expect_offense(<<~ERB)
        <%= form_with model: @user do |f| %>
          <%= f.text_field :name %>
            <% end %>
        <div class="a">
          <%= x %>
            </div>
        <% items.each do |item| %>
          <% item.children.each do |child|
               child.save(item)
          ^^^^^ Layout/IndentationWidth: Use 2 (not 5) spaces for indentation.
          end %>
          ^^^ Layout/BlockAlignment: `end` at 10, 2 is not aligned with `item.children.each do |child|` at 8, 5.
        <% end %>
      ERB

      expect_correction(<<~ERB)
        <%= form_with model: @user do |f| %>
          <%= f.text_field :name %>
            <% end %>
        <div class="a">
          <%= x %>
            </div>
        <% items.each do |item| %>
          <% item.children.each do |child|
               child.save(item)
             end %>
        <% end %>
      ERB
    end
  end

  context "when analyzing bodies indented by the HTML structure" do
    it "triggers Layout/IndentationWidth only for the conditional in a single ERB tag" do
      expect_offense(<<~ERB)
        <ul>
          <% items.each do |item| %>
            <li><%= item %></li>
          <% end %>
        </ul>
        <% if a %>
              <%= a %>
        <% else %>
             <p>
          <%= c %>
             </p>
        <% end %>
        <% while q %>
         <%# comment %>
              <%= q %>
        <% end %>
        <% until r %>
         <%# comment %>
              <p>r</p>
        <% end %>
        <% unless s %>
          <%
            foo(s) %>
        <% end %>
        <% unless t %>
          <% # comment %>
              <%= t %>
        <% end %>
        <div class="a">
              <%= v %>
        </div>
        <% if z
               foo
           ^^^^ Layout/IndentationWidth: Use 2 (not 4) spaces for indentation.
           else
             bar
           end %>
      ERB

      expect_correction(<<~ERB)
        <ul>
          <% items.each do |item| %>
            <li><%= item %></li>
          <% end %>
        </ul>
        <% if a %>
              <%= a %>
        <% else %>
             <p>
          <%= c %>
             </p>
        <% end %>
        <% while q %>
         <%# comment %>
              <%= q %>
        <% end %>
        <% until r %>
         <%# comment %>
              <p>r</p>
        <% end %>
        <% unless s %>
          <%
            foo(s) %>
        <% end %>
        <% unless t %>
          <% # comment %>
              <%= t %>
        <% end %>
        <div class="a">
              <%= v %>
        </div>
        <% if z
             foo
           else
             bar
           end %>
      ERB
    end
  end

  context "when analyzing conditional branches differing only in HTML content" do
    it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
        <% case b %>
        <% when 1 %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
        <% if c %>
          <p class="<%= klass %>">a</p>
        <% else %>
          <p class="<%= klass %>">b</p>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches differing only in text content" do
    it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          hello
        <% else %>
          world
        <% end %>
        <% if b %>
          こんにちは
        <% else %>
          さようなら
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches containing the same escaped ERB tags" do
    it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <%% foo %>
        <% else %>
          <%% foo %>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches with the same expression after different escaped ERB tags" do
    it "does not autocorrect Style/IdenticalConditionalBranches as it drops the escaped ERB tags" do
      expect_offense(<<~ERB)
        <% if b %>
          <%% x %> <%= y %>
                   ^^^^^ Style/IdenticalConditionalBranches: Move `_ = y` out of the conditional.
        <% else %>
          <%% z %> <%= y %>
                   ^^^^^ Style/IdenticalConditionalBranches: Move `_ = y` out of the conditional.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing escaped ERB tags" do
    it "does not check the code in them as they are text" do
      expect_no_offenses(<<~ERB)
        <p><%%= "hello" %></p>
        <pre>
          <%% if user %>
            <%%= user.name %>
          <%% end %>
        </pre>
      ERB
    end
  end

  context "when analyzing a rubocop directive in an escaped ERB comment tag" do
    it "does not apply the directive as it is text" do
      expect_offense(<<~ERB)
        <%%# rubocop:disable Style/StringLiterals %>
        <%= "x" %>
            ^^^ Style/StringLiterals: Prefer single-quoted strings when you don't need string interpolation or special symbols.
      ERB

      expect_correction(<<~ERB)
        <%%# rubocop:disable Style/StringLiterals %>
        <%= 'x' %>
      ERB
    end
  end

  context "when analyzing conditional branches differing only in text too short to be rendered in the Ruby code" do
    it "triggers Style/IdenticalConditionalBranches but not Lint/DuplicateBranch" do
      expect_offense(<<~ERB)
        <% if a %>
          <%= x %>a
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% else %>
          <%= x %>b
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing conditional branches in an attribute differing only in text not rendered in the Ruby code" do
    it "does not trigger Lint/DuplicateBranch" do
      expect_no_offenses(<<~ERB)
        <p class="<% if b %>abc<%= x %><% elsif c %>def<%= x %><% end %>"></p>
      ERB
    end
  end

  context "when analyzing conditionals on a single line having the same Ruby code in all branches" do
    it "triggers Lint/DuplicateBranch only, as Style/IdenticalConditionalBranches crashes on them" do
      expect_offense(<<~ERB)
        <% if a %><%= x %><% else %><%= x %><% end %>
                             ^^^^ Lint/DuplicateBranch: Duplicate branch body detected.
        <% if b %><%= y %><% elsif c %><%= y %><% else %><%= y %><% end %>
                                                  ^^^^ Lint/DuplicateBranch: Duplicate branch body detected.
                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Lint/DuplicateBranch: Duplicate branch body detected.
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing conditional branches containing the same HTML and different Ruby code" do
    it "does not trigger Style/IdenticalConditionalBranches" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <p><%= x %></p>
        <% else %>
          <p><%= y %></p>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches containing different HTML and the same Ruby code" do
    it "triggers Style/IdenticalConditionalBranches only for the Ruby code" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>a</p>
          <%= x %>
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% else %>
          <p>b</p>
          <%= x %>
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing conditional branches containing the same Ruby code inside different open tags" do
    it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <input type="text" <%= x %>>
        <% else %>
          <input type="password" <%= x %>>
        <% end %>
      ERB
    end
  end

  context "when analyzing elsif, in and rescue branches differing only in HTML content" do
    it "does not trigger Lint/DuplicateBranch" do
      expect_no_offenses(<<~ERB)
        <% if a %>
          <p>a</p>
        <% elsif b %>
          <p>b</p>
        <% end %>
        <% case c %>
        <% in 1 %>
          <p>a</p>
        <% in 2 %>
          <p>b</p>
        <% end %>
        <% begin %>
          <%= x %>
        <% rescue A %>
          <p>a</p>
        <% rescue B %>
          <p>b</p>
        <% end %>
        <% items.each do |item| %>
          <%= item %>
        <% rescue A %>
          <p>a</p>
        <% rescue B %>
          <p>b</p>
        <% end %>
      ERB
    end
  end

  context "when analyzing conditional branches containing only the same Ruby code" do
    it "triggers Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
      expect_offense(<<~ERB)
        <% if a %>
          <%= x %>
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% else %>
           ^^^^ Lint/DuplicateBranch: Duplicate branch body detected.
          <%= x %>
          ^^^^^ Style/IdenticalConditionalBranches: Move `_ = x` out of the conditional.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing else branches and when branches containing only HTML" do
    it "does not trigger Style/EmptyElse and Lint/EmptyWhen" do
      expect_no_offenses(<<~ERB)
        <% case a %>
        <% when 1 %>
          a
        <% else %>
          b
        <% end %>
      ERB
    end
  end

  context "when analyzing blocks containing only HTML" do
    it "does not trigger Lint/EmptyBlock" do
      expect_no_offenses(<<~ERB)
        <% items.each do %>
          i
        <% end %>
        <%= form_with do %>
          f
        <% end %>
      ERB
    end
  end

  context "when analyzing else branches and when branches without any content" do
    it "triggers Style/EmptyElse and Lint/EmptyWhen" do
      expect_offense(<<~ERB)
        <% case a %>
        <% when 1 %>
           ^^^^^^ Lint/EmptyWhen: Avoid `when` branches without a body.
        <% else %>
           ^^^^ Style/EmptyElse: Redundant `else`-clause.
        <% end %>
      ERB

      expect_correction(<<~ERB)
        <% case a %>
        <% when 1 %>
        <% end %>
      ERB
    end
  end

  context "when analyzing blocks without any content" do
    it "triggers Lint/EmptyBlock" do
      expect_offense(<<~ERB)
        <% items.each do |item| %>
           ^^^^^^^^^^^^^^^^^^^^^^^ Lint/EmptyBlock: Empty block detected.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing in branches containing only HTML" do
    it "triggers Lint/EmptyInPattern only for in branches without any content" do
      expect_offense(<<~ERB)
        <% case a %>
        <% in 1 %>
          a
        <% in 2 %>
           ^^^^ Lint/EmptyInPattern: Avoid `in` branches without a body.
        <% end %>
      ERB

      expect_no_corrections
    end
  end

  context "when analyzing a simple ERB file without a trailing newline" do
    it "does not trigger any cops" do
      # Written in a string literal, as heredocs end with a newline
      expect_no_offenses("<%= 'Hello world' %>")
    end
  end

  context "when analyzing a control flow ERB tag with a trailing Ruby comment followed by its end tag" do
    it "does not trigger Lint/Syntax" do
      expect_no_offenses(<<~ERB)
        <% if x # comment %>a<% end %>
      ERB
    end
  end

  context "when analyzing ERB tags split into multiple nodes" do
    it "processes the file without extractor errors" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>a</p>
        <% else; end %>
           ^^^^ Style/EmptyElse: Redundant `else`-clause.
      ERB

      expect_correction(<<~ERB)
        <% if a %>
          <p>a</p>
        <% end %>
      ERB
    end
  end

  context "when analyzing trailing whitespace rendered by the conversion" do
    it "triggers Layout/TrailingWhitespace only for the trailing whitespace written in an ERB tag" do
      # Trailing whitespace is written as `\s` not to put trailing whitespace in this file
      expect_offense(<<~ERB)
        <div>
          <%= @a %>
        </div>
        <%
          @e = 1\s\s
                ^^ Layout/TrailingWhitespace: Trailing whitespace detected.
          @f = 2
        %>
        <p>x</p>\s\s
        <%= @b %>\s\s
      ERB

      expect_correction(<<~ERB)
        <div>
          <%= @a %>
        </div>
        <%
          @e = 1
          @f = 2
        %>
        <p>x</p>\s\s
        <%= @b %>\s\s
      ERB
    end
  end

  context "when analyzing case-in (pattern matching)" do
    it "processes the file without extractor errors" do
      expect_offense(<<~ERB)
        <% case a %>
        <% in 1 %>
          <p>one</p>
        <% in Integer => n %>
          <%= n %>
          <%= "n" %>
              ^^^ Style/StringLiterals: Prefer single-quoted strings when you don't need string interpolation or special symbols.
        <% end %>
        <% case b %><% in 1 %>x<% end %>
      ERB

      expect_correction(<<~ERB)
        <% case a %>
        <% in 1 %>
          <p>one</p>
        <% in Integer => n %>
          <%= n %>
          <%= 'n' %>
        <% end %>
        <% case b %><% in 1 %>x<% end %>
      ERB
    end
  end

  context "when analyzing open tags whose tag name is followed by a newline" do
    it "does not trigger any cops" do
      expect_no_offenses(<<~ERB)
        <div
          class="<%= x %>"><% if y %>
          <%= z %>
        <% end %>
        </div>
        <div
          class="<%= #{"x" * 100} %>">
        </div>
      ERB
    end
  end

  context "when an operator without surrounding spaces is written in an ERB tag inside HTML" do
    it "adds the spaces in the tag" do
      expect_offense(<<~ERB)
        <div><%= x==1 %></div>
                  ^^ Layout/SpaceAroundOperators: Surrounding space missing for operator `==`.
      ERB

      expect_correction(<<~ERB)
        <div><%= x == 1 %></div>
      ERB
    end
  end

  context "when string literals are concatenated in an ERB tag inside HTML" do
    it "replaces the concatenation with a string in the tag" do
      expect_offense(<<~ERB)
        <p><%= 'Hello' + 'World' %></p>
               ^^^^^^^^^^^^^^^^^ Style/StringConcatenation: Prefer string interpolation to string concatenation.
      ERB

      expect_correction(<<~ERB)
        <p><%= 'HelloWorld' %></p>
      ERB
    end
  end

  context "when a method call with arguments is written in an ERB tag without whitespace around the code",
          rubocop_config: { "Style/MethodCallWithArgsParentheses" => { "Enabled" => true } } do
    it "adds the parentheses in the tag" do
      expect_offense(<<~ERB)
        <%=foo 1%>
           ^^^^^ Style/MethodCallWithArgsParentheses: Use parentheses for method calls with arguments.
      ERB

      expect_correction(<<~ERB)
        <%=foo(1)%>
      ERB
    end
  end

  context "when the length is compared with zero in an ERB tag" do
    it "replaces the comparison with `empty?`" do
      expect_offense(<<~ERB)
        <%= arr.length == 0 %>
            ^^^^^^^^^^^^^^^ Style/NumericPredicate: Use `arr.length.zero?` instead of `arr.length == 0`.
            ^^^^^^^^^^^^^^^ Style/ZeroLengthPredicate: Use `empty?` instead of `length == 0`.
      ERB

      expect_correction(<<~ERB)
        <%= arr.empty? %>
      ERB
    end
  end

  context "when a hash literal with misaligned keys spans multiple lines in an ERB tag" do
    it "aligns the keys in the tag" do
      expect_offense(<<~ERB)
        <%= render locals: {
          foo: 1,
          barbaz:   2
          ^^^^^^^^^^^ Layout/HashAlignment: Align the keys of a hash literal if they span more than one line.
        } %>
      ERB

      expect_correction(<<~ERB)
        <%= render locals: {
          foo: 1,
          barbaz: 2
        } %>
      ERB
    end
  end

  context "when an empty else branch follows a branch containing HTML" do
    it "removes the else tag and keeps the HTML" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>x</p>
        <% else %>
           ^^^^ Style/EmptyElse: Redundant `else`-clause.
        <% end %>
      ERB

      expect_correction(<<~ERB)
        <% if a %>
          <p>x</p>
        <% end %>
      ERB
    end
  end

  context "when a negated condition has an else branch and the branches contain HTML" do
    it "reports the offense as not correctable" do
      expect_offense(<<~ERB)
        <% if !foo %>
           ^^^^^^^^^^ Style/NegatedIfElseCondition: Invert the negated condition and swap the if-else branches.
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
      ERB

      expect(run_rubocop(last_source).map(&:correctable?)).to eq [false]
      expect_no_corrections
    end
  end

  context "when a conditional containing HTML is nested in the else branch of a conditional containing HTML" do
    it "reports the offense as not correctable" do
      expect_offense(<<~ERB)
        <% if a %>
          <p>x</p>
        <% else %>
          <% if b %>
             ^^ Style/IfInsideElse: Convert `if` nested inside `else` to `elsif`.
            <p>y</p>
          <% end %>
        <% end %>
      ERB

      expect(run_rubocop(last_source).map(&:correctable?)).to eq [false]
      expect_no_corrections
    end
  end

  context "when a literal is written in an ERB tag alone on its line" do
    it "removes the line of the tag" do
      expect_offense(<<~ERB)
        <p>a</p>
          <% 1 %>
             ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <p>a</p>
        <%= b %>
      ERB
    end
  end

  context "when a literal is written in an ERB tag on the first line" do
    it "removes the line of the tag" do
      expect_offense(<<~ERB)
        <% 1 %>
           ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <%= b %>
      ERB
    end
  end

  context "when a literal is written in an ERB tag next to HTML" do
    it "removes the tag" do
      expect_offense(<<~ERB)
        <p><% 1 %></p>
              ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <p></p>
        <%= b %>
      ERB
    end
  end

  context "when a literal is written in an ERB tag next to another ERB tag" do
    it "removes the tag" do
      expect_offense(<<~ERB)
        <% 1 %><%= b %>
           ^ Lint/Void: Literal `1` used in void context.
      ERB

      expect_correction(<<~ERB)
        <%= b %>
      ERB
    end
  end

  context "when a literal is written in an ERB tag following another ERB tag with a space between them" do
    it "removes the tag and the space before it" do
      expect_offense(<<~ERB)
        <%= a %> <% 1 %>
                    ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <%= a %>
        <%= b %>
      ERB
    end
  end

  context "when literals are written in all the ERB tags on a line" do
    it "removes the line of the tags" do
      expect_offense(<<~ERB)
        <% 1 %> <% 2 %>
           ^ Lint/Void: Literal `1` used in void context.
                   ^ Lint/Void: Literal `2` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <%= b %>
      ERB
    end
  end

  context "when a literal is written in an ERB tag on a line after multi-byte characters" do
    it "removes the line of the tag" do
      expect_offense(<<~ERB)
        <p>日本語🍣</p>
        <% 1 %>
           ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <p>日本語🍣</p>
        <%= b %>
      ERB
    end
  end

  context "when a literal follows other code in an ERB tag" do
    it "removes the literal and keeps the tag" do
      expect_offense(<<~ERB)
        <% foo; 1 %>
                ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <% foo; %>
        <%= b %>
      ERB
    end
  end

  context "when a literal is followed by a comment in an ERB tag" do
    it "removes the literal and keeps the tag" do
      expect_offense(<<~ERB)
        <% 1 # comment %>
           ^ Lint/Void: Literal `1` used in void context.
        <%= b %>
      ERB

      expect_correction(<<~ERB)
        <% # comment %>
        <%= b %>
      ERB
    end
  end

  context "when HTML has consecutive blank lines" do
    it "reports the offense as not correctable" do
      expect_offense(<<~ERB)
        <p>a</p>


        ^{} Layout/EmptyLines: Extra blank line detected.
        <p>b</p>
      ERB

      expect(run_rubocop(last_source).map(&:correctable?)).to eq [false]
      expect_no_corrections
    end
  end

  context "when unless-else branches containing HTML are followed by an operator without surrounding spaces" do
    it "adds the spaces around the operator only" do
      expect_offense(<<~ERB)
        <% unless foo %>
           ^^^^^^^^^^^^^ Style/UnlessElse: Do not use `unless` with `else`. Rewrite these with the positive case first.
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
        <%= x==1 %>
             ^^ Layout/SpaceAroundOperators: Surrounding space missing for operator `==`.
      ERB

      corrected = <<~ERB
        <% unless foo %>
          <p>a</p>
        <% else %>
          <p>b</p>
        <% end %>
        <%= x == 1 %>
      ERB
      expect_correction(corrected)
      # Without inserting rubocop:todo comments for the uncorrectable offense
      expect_correction(corrected, disable_uncorrectable: true)
    end
  end

  context "when a useless assignment of a literal is written in an ERB tag alone on its line" do
    it "removes the line of the tag" do
      expect_offense(<<~ERB)
        <p>a</p>
        <% unused = 1 %>
           ^^^^^^ Lint/UselessAssignment: Useless assignment to variable - `unused`.
        <%= b %>
      ERB

      # Lint/UselessAssignment leaves `<% 1 %>`, Lint/Void leaves `<% %>`, then Herb/EmptyErbTag removes the line
      # as the statement is removed in Ruby files
      expect_correction(<<~ERB)
        <p>a</p>
        <%= b %>
      ERB
    end
  end

  context "when analyzing an empty ERB tag on the last line without a newline" do
    # Written in a string literal, as heredocs end with a newline
    let(:source) { "<p>a</p>\n<% %>" }

    it "triggers Herb/EmptyErbTag and removes the line of the tag" do
      offenses = run_rubocop(source).map { [_1.cop_name, _1.line, _1.column] }
      expect(offenses).to eq [["Herb/EmptyErbTag", 2, 0]]

      expect(autocorrect(source)).to eq "<p>a</p>\n"
    end
  end

  # Written in string literals, as annotations would not line up with CR escaped in heredocs
  context "with CR in the source" do
    context "when analyzing ERB with CRLF line endings" do
      let(:source) { "<div>\r\n  <p>\r\n    <%= a %>\r\n    <%= x==1 %>\r\n  </p>\r\n</div>\r\n" }

      it "reports the same offenses as the LF equivalent besides Layout/EndOfLine" do
        offenses = run_rubocop(source).map { [_1.cop_name, _1.line, _1.column] }
        expect(offenses).to eq [["Layout/EndOfLine", 1, 0], ["Layout/SpaceAroundOperators", 4, 9]]

        # Parser::Source::Buffer normalizes CRLF to LF, as it does for Ruby files
        expect(autocorrect(source)).to eq "<div>\n  <p>\n    <%= a %>\n    <%= x == 1 %>\n  </p>\n</div>\n"
      end
    end

    context "when literals are written in ERB tags with CRLF line endings" do
      let(:source) { "<p>a</p>\r\n  <% 1 %>\r\n<p><% 2 %></p>\r\n<%= b %>\r\n" }

      it "corrects the offenses as the LF equivalent" do
        offenses = run_rubocop(source).map { [_1.cop_name, _1.line, _1.column] }
        expect(offenses).to eq [["Layout/EndOfLine", 1, 0], ["Lint/Void", 2, 5], ["Lint/Void", 3, 6]]

        expect(autocorrect(source)).to eq "<p>a</p>\n<p></p>\n<%= b %>\n"
      end
    end

    context "when analyzing ERB with mixed line endings" do
      let(:source) { "<div>\n  <%= a %>\r\n</div>\n" }

      it "triggers Layout/EndOfLine only at the line ending with CRLF" do
        offenses = run_rubocop(source).map { [_1.cop_name, _1.line, _1.column] }
        expect(offenses).to eq [["Layout/EndOfLine", 2, 0]]

        expect(autocorrect(source)).to eq source
      end
    end

    context "when analyzing ERB with lone carriage returns" do
      let(:source) { "<div>\r  <%= x==1 %>\r</div>\n<%= y==2 %>\n" }

      it "does not treat them as line breaks" do
        offenses = run_rubocop(source).map { [_1.cop_name, _1.line, _1.column] }
        expect(offenses).to eq [["Layout/SpaceAroundOperators", 1, 13], ["Layout/SpaceAroundOperators", 2, 5]]

        expect(autocorrect(source)).to eq "<div>\r  <%= x == 1 %>\r</div>\n<%= y == 2 %>\n"
      end
    end
  end
end
