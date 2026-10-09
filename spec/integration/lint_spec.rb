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
      f.write(YAML.dump(RuboCop::Herb::Configuration.to_rubocop_config))
      f.close
    end
  end
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

    context "when analyzing block in output tag closed by end tag" do
      let(:source) do
        <<~ERB
          <%= form_with model: @user do |f| %>
            <%= f.text_field :name %>
          <% end %>
        ERB
      end

      it "does not trigger Layout/BlockAlignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
      end
    end

    context "when analyzing block whose end tag follows HTML" do
      let(:source) do
        <<~ERB
          <% items.each do |item| %>
          <p><%= item %></p><% end %>
        ERB
      end

      it "does not trigger Layout/BlockAlignment" do
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

    context "with Lint/EmptyBlock enabled" do
      # Lint/EmptyBlock is a pending cop, so enable it explicitly
      let(:config) do
        Tempfile.new([".rubocop", ".yml"]).tap do |f|
          rubocop_config = RuboCop::Herb::Configuration.to_rubocop_config
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
          rubocop_config = RuboCop::Herb::Configuration.to_rubocop_config
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

    context "when analyzing block in output tag closed by end tag" do
      let(:source) do
        <<~ERB
          <%= form_with model: @user do |f| %>
            <%= f.text_field :name %>
          <% end %>
        ERB
      end

      it "does not trigger Layout/BlockAlignment" do
        runner.run(path, source, {})
        offenses = runner.offenses.map(&:cop_name)
        expect(offenses).to eq []
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
  end
end
