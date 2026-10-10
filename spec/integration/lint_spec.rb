# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/lsp/stdin_runner"
require "tempfile"
require "yaml"

RSpec.describe "Lint with RuboCop", type: :feature do
  let(:runner) { RuboCop::Lsp::StdinRunner.new(config_store) }
  let(:config_store) do
    RuboCop::ConfigStore.new.tap do |store|
      store.options_config = config.path
    end
  end
  let(:config) do
    Tempfile.new([".rubocop", ".yml"]).tap do |f|
      f.write(YAML.dump(rubocop_config))
      f.close
    end
  end
  # Herb/Linting is tested in herb_lint_spec.rb
  let(:rubocop_config) { RuboCop::Herb::Configuration.to_rubocop_config.merge("Herb/Linting" => { "Enabled" => false }) }
  let(:path) { "test.html.erb" }

  before do
    RuboCop::Herb::Configuration.setup({ "html_visualization" => html_visualization })
    RuboCop::Lsp::StdinRunner.ruby_extractors.unshift(RuboCop::Herb::Extractor)
  end

  after do
    config.unlink
    RuboCop::Lsp::StdinRunner.ruby_extractors.shift
  end

  context "when html_visualization is disabled (default)" do
    let(:html_visualization) { false }

    context "when analyzing an simple ERB file" do
      let(:source) { "<%= 'Hello world' %>" }

      it "detects offenses" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else-end with output tags" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <%= value1 %>
          <% else %>
            <%= value2 %>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else-end with output tags wrapped in HTML elements" do
      let(:source) do
        <<~ERB
          <% if page.current? %>
            <li class="active"><%= content_tag :a, page %></li>
          <% else %>
            <li><%= link_to page, url %></li>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing each block with output tags" do
      let(:source) do
        <<~ERB
          <% items.each do |item| %>
            <%= item %>
          <% end %>
        ERB
      end

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if block with output tag followed by non-output tag" do
      let(:source) do
        <<~ERB
          <% if foo? %>
            <%= 'close' if bar? %>
            <% :foo %>
          <% end %>
        ERB
      end

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if block with output tag followed by another output tag" do
      let(:source) do
        <<~ERB
          <div>
            <% if @error %>
              <div><%= @error %></div>
            <% end %>
            <div><%= render 'index' %></div>
          </div>
        ERB
      end

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing ERB with multi-byte characters in comments" do
      let(:source) do
        <<~ERB
          <div class="form">
            <%# 日本語コメント %>
            <div class="inner">
              <input value="<%= foo.bar %>" />
              <label><%= baz(qux: @value) %></label>
            </div>
          </div>
        ERB
      end

      it "does not trigger Layout/SpaceBeforeFirstArg" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing conditional branches containing only HTML" do
      let(:source) do
        <<~ERB
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

      it "does not trigger Lint/EmptyConditionalBody" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing conditional branches without any content" do
      let(:source) do
        <<~ERB
          <% if a %>
          <% elsif b %>
            <%= b %>
          <% end %>
          <% unless c %>
          <% end %>
        ERB
      end

      it "triggers Lint/EmptyConditionalBody" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Lint/EmptyConditionalBody", 1], ["Lint/EmptyConditionalBody", 5]]
      end
    end

    context "when analyzing an empty if branch followed by an elsif branch containing only HTML" do
      let(:source) do
        <<~ERB
          <% if a %>
          <% elsif b %>
            <p>b</p>
          <% end %>
        ERB
      end

      it "triggers Lint/EmptyConditionalBody only for the empty if branch" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Lint/EmptyConditionalBody", 1]]
      end
    end

    context "when analyzing rescue and ensure clauses containing only HTML" do
      let(:source) do
        <<~ERB
          <% begin %>
            <p>x</p>
          <% rescue StandardError %>
            <p>error</p>
          <% ensure %>
            <p>done</p>
          <% end %>
        ERB
      end

      it "does not trigger Lint/SuppressedException and Lint/EmptyEnsure" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing rescue and ensure clauses without any content" do
      let(:source) do
        <<~ERB
          <% begin %>
            <p>x</p>
          <% rescue StandardError %>
          <% ensure %>
          <% end %>
        ERB
      end

      it "triggers Lint/SuppressedException and Lint/EmptyEnsure" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Lint/SuppressedException", 3], ["Lint/EmptyEnsure", 4]]
      end
    end

    context "when analyzing conditionals written across ERB tags on a single line" do
      let(:source) do
        <<~ERB
          <% if a %>foo<% elsif b %><% end %>
          <% if a %><%= x %><% else %><%= y %><% end %>
          <% unless a %><%= x %><% else %><%= y %><% end %>
        ERB
      end

      it "does not trigger Style/OneLineConditional" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/UnlessElse", 3]]
      end
    end

    context "when analyzing a conditional written in a single ERB tag" do
      let(:source) { "<% if a then b else c end %>\n" }

      it "triggers Style/OneLineConditional" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/OneLineConditional", 1]]
      end
    end

    context "when analyzing conditionals written across ERB tags and in a single ERB tag" do
      let(:source) do
        <<~ERB
          <% if a %>
            <p>a</p>
          <% elsif b %>
            <p>b</p>
          <% end %>
          <% unless c %>
            <%= c %>
          <% end %>
          <% if d; foo; end %>
        ERB
      end

      it "triggers Style/IfWithSemicolon and Style/IfUnlessModifier only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/IfUnlessModifier", 9], ["Style/IfWithSemicolon", 9]]
      end
    end

    context "when analyzing case statements with output tags and a conditional assignment in a single ERB tag" do
      let(:source) do
        <<~ERB
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
               @z = 1
             else
               @z = 2
             end %>
        ERB
      end

      it "triggers Style/ConditionalAssignment only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/ConditionalAssignment", 13]]
      end
    end

    context "when analyzing conditionals whose branches output the condition" do
      let(:source) do
        <<~ERB
          <% if a %>
            <p><%= a %></p>
          <% else %>
            <p><%= b %></p>
          <% end %>
          <% if c %>
            <%= c %>
          <% end %>
          <%= if d
                d
              else
                e
              end %>
        ERB
      end

      it "triggers Style/RedundantCondition only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/RedundantCondition", 9]]
      end
    end

    context "when analyzing conditionals at the end of blocks" do
      let(:source) do
        <<~ERB
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
                 save(other)
                 notify(other)
                 log(other)
               end
             end %>
        ERB
      end

      it "triggers Style/Next only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/Next", 11]]
      end
    end

    context "when analyzing blocks written across ERB tags" do
      let(:source) do
        <<~ERB
          <p class="a"><%= x %></p>
          <% items.each do |item| %><b><%= item %></b><% end %>
          <%= form_with do |f| %><%= f.text_field :name %><% end %>
          <% others.each do |other| %>
            <%= other %>
          <% end %>
          <% foos.each { |foo| %>
            <%= foo %>
          <% } %>
          <% bars.each do |bar| save(bar) end %>
        ERB
      end

      it "triggers Style/BlockDelimiters only for the multi-line brace block and the block in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/BlockDelimiters", 7], ["Style/BlockDelimiters", 10]]
      end
    end

    context "when analyzing conditionals and loops whose end tags follow HTML" do
      let(:source) do
        <<~ERB
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

      it "triggers Layout/EndAlignment only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/EndAlignment", 13]]
      end
    end

    context "when analyzing blocks whose end tags follow the HTML structure" do
      # The misaligned `end` also triggers Layout/IndentationWidth, which measures the body from `end`
      let(:rubocop_config) { super().merge("Layout/IndentationWidth" => { "Enabled" => false }) }
      let(:source) do
        <<~ERB
          <%= form_with model: @user do |f| %>
            <%= f.text_field :name %>
              <% end %>
          <% items.each do |item| %>
          <p><%= item %></p><% end %>
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

      it "triggers Layout/BlockAlignment only for the block in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/BlockAlignment", 12]]
      end
    end

    context "when analyzing bodies indented by the HTML structure" do
      let(:source) do
        <<~ERB
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
            <% # note %>
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

      it "triggers Layout/IndentationWidth only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/IndentationWidth", 33]]
      end
    end

    context "when analyzing statements indented by the HTML structure" do
      let(:source) do
        <<~ERB
          <div>
            <% @a = 1 %>
              <% @b = 2 %>
            <p><%= @a %></p>
          </div>
          <% items.each do |item| %>
            <p><%= item %></p>
                <%= item.name %>
          <% end %>
          <% others.each do |other|
               x = other.name
                 y = other.size
               foo(x, y)
             end %>
        ERB
      end

      it "triggers Layout/IndentationConsistency only for the statements in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/IndentationConsistency", 12]]
      end
    end

    context "when analyzing comments indented by the HTML structure" do
      let(:source) do
        <<~ERB
          <div>
            <%# header %>
              <%= @x %>
            <% # label %>
                <p><%= @y %></p>
          </div>
          <% @items.each do |item|
               # aligned
               item.save
                 # misaligned
               item.reload
             end %>
          <% # last %>
        ERB
      end

      it "triggers Layout/CommentIndentation only for the comment in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/CommentIndentation", 10]]
      end
    end

    context "when analyzing control flows whose branches output values followed by HTML" do
      let(:source) do
        <<~ERB
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

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "with Lint/DuplicateBranch enabled" do
      # Lint/DuplicateBranch is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Lint/DuplicateBranch" => { "Enabled" => true })))
          f.close
        end
      end

      context "when analyzing conditional branches differing only in HTML content" do
        let(:source) do
          <<~ERB
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
          ERB
        end

        it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing conditional branches containing different HTML and the same Ruby code" do
        let(:source) do
          <<~ERB
            <% if a %>
              <p>a</p>
              <%= x %>
            <% else %>
              <p>b</p>
              <%= x %>
            <% end %>
          ERB
        end

        it "triggers Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Style/IdenticalConditionalBranches", 3],
                                  ["Lint/DuplicateBranch", 4],
                                  ["Style/IdenticalConditionalBranches", 6]]
        end
      end

      context "when analyzing conditional branches containing the same Ruby code inside different HTML" do
        let(:source) do
          <<~ERB
            <% if a %>
              <div class="a"><%= x %></div>
            <% else %>
              <div class="b"><%= x %></div>
            <% end %>
          ERB
        end

        it "does not trigger Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Lint/DuplicateBranch", 3]]
        end
      end
    end

    context "with Lint/EmptyBlock enabled" do
      # Lint/EmptyBlock is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Lint/EmptyBlock" => { "Enabled" => true })))
          f.close
        end
      end

      context "when analyzing else branches, when branches and blocks containing only HTML" do
        let(:source) do
          <<~ERB
            <% case a %>
            <% when 1 %>
              <p>a</p>
            <% else %>
              <p>b</p>
            <% end %>
            <% items.each do |item| %>
              <p>item</p>
            <% end %>
            <%= form_with do |f| %>
              <p>form</p>
            <% end %>
          ERB
        end

        it "does not trigger Style/EmptyElse, Lint/EmptyWhen and Lint/EmptyBlock" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing else branches, when branches and blocks without any content" do
        let(:source) do
          <<~ERB
            <% case a %>
            <% when 1 %>
            <% else %>
            <% end %>
            <% items.each do |item| %>
            <% end %>
          ERB
        end

        it "triggers Style/EmptyElse, Lint/EmptyWhen and Lint/EmptyBlock" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Lint/EmptyWhen", 2], ["Style/EmptyElse", 3], ["Lint/EmptyBlock", 5]]
        end
      end
    end

    context "when analyzing case-in (pattern matching)" do
      let(:source) do
        <<~ERB
          <% case a %>
          <% in 1 %>
            <p>one</p>
          <% in Integer => n %>
            <%= n %>
            <%= "n" %>
          <% end %>
          <% case b %><% in 1 %>x<% end %>
        ERB
      end

      it "processes the file without extractor errors" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/StringLiterals", 6]]
      end
    end

    context "with Lint/EmptyInPattern enabled" do
      # Lint/EmptyInPattern is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Lint/EmptyInPattern" => { "Enabled" => true })))
          f.close
        end
      end

      context "when analyzing in branches containing only HTML" do
        let(:source) do
          <<~ERB
            <% case a %>
            <% in 1 %>
              <p>a</p>
            <% in 2 %>
            <% end %>
          ERB
        end

        it "triggers Lint/EmptyInPattern only for in branches without any content" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Lint/EmptyInPattern", 4]]
        end
      end
    end
  end

  context "when html_visualization is enabled" do
    let(:html_visualization) { true }

    context "when analyzing an simple ERB file" do
      let(:source) { "<%= 'Hello world' %>" }

      it "detects offenses" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else-end with output tags" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <%= value1 %>
          <% else %>
            <%= value2 %>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else-end with output tags wrapped in HTML elements" do
      let(:source) do
        <<~ERB
          <% if page.current? %>
            <li class="active"><%= content_tag :a, page %></li>
          <% else %>
            <li><%= link_to page, url %></li>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing each block with output tags with HTML close tags" do
      let(:source) do
        <<~ERB
          <ul>
            <% items.each do |item| %>
              <li><%= item %></li>
            <% end %>
          </ul>
        ERB
      end

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if block with output tag followed by another output tag" do
      let(:source) do
        <<~ERB
          <div>
            <% if @error %>
              <div><%= @error %></div>
            <% end %>
            <div><%= render 'index' %></div>
          </div>
        ERB
      end

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing block with HTML content on single line" do
      let(:source) { "<%= link_to root_path do %><span>Home</span><% end %>" }

      it "does not trigger Style/SingleLineDoEndBlock" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing multiple output tags" do
      let(:source) do
        <<~ERB
          <%= content_for(:page_title) %>
          <% items.each do |item| %>
            <%= item %>
          <% end %>
        ERB
      end

      it "does not trigger Lint/UnderscorePrefixedVariableName" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing yield ERB tag inside HTML element" do
      let(:source) do
        <<~ERB
          <div class="portlet-body form">
            <div class="form-body"><%= yield if block_given? %></div>
          </div>
        ERB
      end

      it "does not trigger Lint/EmptyBlock" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing output tag inside HTML attribute" do
      let(:source) { '<th class="<%= class_name %>"><%= content %></th>' }

      it "does not trigger Layout/SpaceAroundOperators" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing HTML element with attributes containing ERB" do
      let(:source) do
        <<~ERB
          <html lang="en">
            <head>
              <title><%= title %></title>
            </head>
          </html>
        ERB
      end

      it "does not trigger Layout/SpaceBeforeBlockBraces" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing block with text node inside" do
      let(:source) { "<%= items.each do %>hello<% end %>" }

      it "does not trigger Style/NumberedParameters" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else with HTML blocks using brace notation" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <div class="foo"><%= @name %></div>
          <% else %>
            <div class="bar"><%= @other %></div>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing if-else with HTML blocks followed by ERB" do
      let(:source) do
        <<~ERB
          <% if condition %>
            <div class="foo"><%= @name %></div>
            <%= @extra %>
          <% else %>
            <div class="bar"><%= @other %></div>
            <%= @extra2 %>
          <% end %>
        ERB
      end

      it "does not trigger Style/ConditionalAssignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing control flows whose branches output values followed by HTML" do
      let(:source) do
        <<~ERB
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

      it "does not trigger Lint/Void" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "with Lint/DuplicateBranch enabled" do
      # Lint/DuplicateBranch is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Lint/DuplicateBranch" => { "Enabled" => true })))
          f.close
        end
      end

      context "when analyzing conditional branches differing only in HTML content" do
        let(:source) do
          <<~ERB
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

        it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing conditional branches differing only in text content" do
        let(:source) do
          <<~ERB
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

        it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing ERB tags split into multiple nodes" do
        let(:source) do
          <<~ERB
            <% if a %>
              <p>a</p>
            <% else; end %>
          ERB
        end

        it "processes the file without extractor errors" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Style/EmptyElse", 3]]
        end
      end

      context "when analyzing conditional branches containing the same HTML and different Ruby code" do
        let(:source) do
          <<~ERB
            <% if a %>
              <p><%= x %></p>
            <% else %>
              <p><%= y %></p>
            <% end %>
          ERB
        end

        it "does not trigger Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing conditional branches containing different HTML and the same Ruby code" do
        let(:source) do
          <<~ERB
            <% if a %>
              <p>a</p>
              <%= x %>
            <% else %>
              <p>b</p>
              <%= x %>
            <% end %>
          ERB
        end

        it "triggers Style/IdenticalConditionalBranches only for the Ruby code" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line, _1.location.source] }
          expect(offenses).to eq [["Style/IdenticalConditionalBranches", 3, "<%= x"],
                                  ["Style/IdenticalConditionalBranches", 6, "<%= x"]]
        end
      end

      context "when analyzing conditional branches containing the same Ruby code inside different open tags" do
        let(:source) do
          <<~ERB
            <% if a %>
              <input type="text" <%= x %>>
            <% else %>
              <input type="password" <%= x %>>
            <% end %>
          ERB
        end

        it "does not trigger Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing elsif, in and rescue branches differing only in HTML content" do
        let(:source) do
          <<~ERB
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

        it "does not trigger Lint/DuplicateBranch" do
          runner.run(path, source, {})
          offenses = runner.offenses.map(&:cop_name)
          expect(offenses).to eq []
        end
      end

      context "when analyzing conditional branches containing only the same Ruby code" do
        let(:source) do
          <<~ERB
            <% if a %>
              <%= x %>
            <% else %>
              <%= x %>
            <% end %>
          ERB
        end

        it "triggers Lint/DuplicateBranch and Style/IdenticalConditionalBranches" do
          runner.run(path, source, {})
          offenses = runner.offenses.map { [_1.cop_name, _1.line] }
          expect(offenses).to eq [["Style/IdenticalConditionalBranches", 2],
                                  ["Lint/DuplicateBranch", 3],
                                  ["Style/IdenticalConditionalBranches", 4]]
        end
      end
    end

    context "when analyzing conditionals whose branches output the condition" do
      let(:source) do
        <<~ERB
          <% if a %>
            <p><%= a %></p>
          <% else %>
            <p><%= b %></p>
          <% end %>
          <% if c %>
            <%= c %>
          <% end %>
          <%= if d
                d
              else
                e
              end %>
        ERB
      end

      it "triggers Style/RedundantCondition only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/RedundantCondition", 9]]
      end
    end

    context "when analyzing conditionals at the end of blocks" do
      let(:source) do
        <<~ERB
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
                 save(other)
                 notify(other)
                 log(other)
               end
             end %>
        ERB
      end

      it "triggers Style/Next only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/Next", 11]]
      end
    end

    context "when analyzing blocks written across ERB tags" do
      let(:source) do
        <<~ERB
          <p class="a"><%= x %></p>
          <% items.each do |item| %><b><%= item %></b><% end %>
          <%= form_with do |f| %><%= f.text_field :name %><% end %>
          <% others.each do |other| %>
            <%= other %>
          <% end %>
          <% foos.each { |foo| %>
            <%= foo %>
          <% } %>
          <% bars.each do |bar| save(bar) end %>
        ERB
      end

      it "triggers Style/BlockDelimiters only for the multi-line brace block and the block in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/BlockDelimiters", 7], ["Style/BlockDelimiters", 10]]
      end
    end

    context "when analyzing conditionals and loops whose end tags follow HTML" do
      let(:source) do
        <<~ERB
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

      it "triggers Layout/EndAlignment only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/EndAlignment", 13]]
      end
    end

    context "when analyzing blocks whose end tags follow the HTML structure" do
      # The misaligned `end` also triggers Layout/IndentationWidth, which measures the body from `end`
      let(:rubocop_config) { super().merge("Layout/IndentationWidth" => { "Enabled" => false }) }
      let(:source) do
        <<~ERB
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

      it "triggers Layout/BlockAlignment only for the block in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/BlockAlignment", 10]]
      end
    end

    context "when analyzing bodies indented by the HTML structure" do
      let(:source) do
        <<~ERB
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
            <% # note %>
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

      it "triggers Layout/IndentationWidth only for the conditional in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/IndentationWidth", 33]]
      end
    end

    context "when analyzing statements indented by the HTML structure" do
      let(:source) do
        <<~ERB
          <div>
            <% @a = 1 %>
              <% @b = 2 %>
            <p><%= @a %></p>
          </div>
          <% items.each do |item| %>
            <p><%= item %></p>
                <%= item.name %>
          <% end %>
          <% others.each do |other|
               x = other.name
                 y = other.size
               foo(x, y)
             end %>
        ERB
      end

      it "triggers Layout/IndentationConsistency only for the statements in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/IndentationConsistency", 12]]
      end
    end

    context "when analyzing comments indented by the HTML structure" do
      let(:source) do
        <<~ERB
          <div>
            <%# header %>
              <%= @x %>
            <% # label %>
                <p><%= @y %></p>
          </div>
          <% @items.each do |item|
               # aligned
               item.save
                 # misaligned
               item.reload
             end %>
          <% # last %>
        ERB
      end

      it "triggers Layout/CommentIndentation only for the comment in a single ERB tag" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/CommentIndentation", 10]]
      end
    end

    context "when analyzing case-in (pattern matching)" do
      let(:source) do
        <<~ERB
          <% case a %>
          <% in 1 %>
            <p>one</p>
          <% in Integer => n %>
            <%= n %>
            <%= "n" %>
          <% end %>
          <% case b %><% in 1 %>x<% end %>
        ERB
      end

      it "processes the file without extractor errors" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/StringLiterals", 6]]
      end
    end

    context "with Layout/SpaceInsideBlockBraces" do
      let(:source) do
        <<~ERB
          <p class="a"><%= x %></p>
          <div class="a"><%= x %>
            <%= y %></div>
          <% items.each {|item| puts item } %>
        ERB
      end

      it "triggers Layout/SpaceInsideBlockBraces only for the Ruby block" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/SpaceInsideBlockBraces", 4]]
      end
    end

    context "with Layout/SpaceBeforeBlockBraces and Layout/SpaceInsideBlockBraces configured to no_space" do
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Layout/SpaceBeforeBlockBraces" => { "EnforcedStyle" => "no_space" },
                                                 "Layout/SpaceInsideBlockBraces" => { "EnforcedStyle" => "no_space" })))
          f.close
        end
      end
      let(:source) do
        <<~ERB
          <p class="a"><%= x %></p>
          <div class="a"><%= x %>
            <%= y %></div>
          <% items.each { |item| puts item } %>
        ERB
      end

      it "triggers Layout/SpaceBeforeBlockBraces and Layout/SpaceInsideBlockBraces only for the Ruby block" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/SpaceBeforeBlockBraces", 4], ["Layout/SpaceInsideBlockBraces", 4]]
      end
    end

    context "with Style/SingleLineDoEndBlock enabled" do
      # Style/SingleLineDoEndBlock is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          f.write(YAML.dump(rubocop_config.merge("Style/SingleLineDoEndBlock" => { "Enabled" => true })))
          f.close
        end
      end
      let(:source) do
        <<~ERB
          <ul class="a"><li class="b"><%= x %></li>
            <li class="b"><%= y %></li>
          </ul>
          <% items.each do |item| %><%= item %><% end %>
        ERB
      end

      it "triggers Style/SingleLineDoEndBlock only for the Ruby block" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Style/SingleLineDoEndBlock", 4]]
      end
    end

    context "when analyzing blocks whose body starts at the line of the block start" do
      let(:source) do
        <<~ERB
          <div class="a"><%= x %>
          </div>
          <p class="a"> text
            <%= y %>
          </p>
          <% items.each do |item| %><%= item %>
          <% end %>
        ERB
      end

      it "triggers Layout/MultilineBlockLayout only for the Ruby block" do
        runner.run(path, source, {})
        offenses = runner.offenses.map { [_1.cop_name, _1.line] }
        expect(offenses).to eq [["Layout/MultilineBlockLayout", 6]]
      end
    end
  end
end
