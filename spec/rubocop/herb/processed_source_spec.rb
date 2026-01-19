# frozen_string_literal: true

RSpec.describe RuboCop::Herb::ProcessedSource do
  def collect_send_sources(node)
    sources = []
    return sources unless node.respond_to?(:type)

    sources << node.source if node.type == :send
    node.children.each { |child| sources.concat(collect_send_sources(child)) }
    sources
  end

  describe "HTML AST restoration" do
    let(:erb_source) { "<div><%= @name %></div>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "restores original HTML source in send nodes" do
      sources = collect_send_sources(processed_source.ast)
      expect(sources).to eq(["<div>", "</div>"])
    end

    it "returns RuboCop AST Node" do
      expect(processed_source.ast).to be_a(RuboCop::AST::Node)
    end
  end

  describe "with multiple HTML tags" do
    let(:erb_source) { "<ul><li><%= item %></li></ul>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "restores all HTML tags" do
      sources = collect_send_sources(processed_source.ast)
      expect(sources).to eq(["<ul>", "<li>", "item", "</li>", "</ul>"])
    end
  end

  describe "with attributes" do
    let(:erb_source) { '<div class="container"><%= content %></div>' }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "restores full HTML tag including attributes" do
      sources = collect_send_sources(processed_source.ast)
      expect(sources).to eq(['<div class="container">', "content", "</div>"])
    end
  end

  describe "without tags" do
    let(:erb_source) { "<div><%= @name %></div>" }
    let(:processed_source) do
      described_class.new("div; @name; div0; ", 3.3, "test.html.erb", hybrid_code: erb_source, tags: {})
    end

    it "keeps original AST unchanged" do
      expect(processed_source.ast).to be_a(RuboCop::AST::Node)
    end
  end

  describe "ERB if-end range adjustment" do
    let(:erb_source) { "<% if true %><% end %>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "adjusts location.end to include full ERB tag" do
      if_node = processed_source.ast

      # The end location should cover "<% end %>" (positions 13-22)
      expect(if_node.location.end.begin_pos..if_node.location.end.end_pos).to eq(13..22)
    end
  end

  describe "ERB if-elsif-else-end range adjustment" do
    let(:erb_source) { "<% if a %><% elsif b %><% else %><% end %>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "adjusts if node keyword to include full ERB tag" do
      if_node = processed_source.ast

      # The keyword location should cover "<% if a %>" (positions 0-10)
      expect(if_node.location.keyword.begin_pos..if_node.location.keyword.end_pos).to eq(0..10)
    end

    it "adjusts elsif node keyword to include full ERB tag" do
      if_node = processed_source.ast
      elsif_node = if_node.else_branch # elsif is represented as nested if

      # The keyword location should cover "<% elsif b %>" (positions 10-23)
      expect(elsif_node.location.keyword.begin_pos..elsif_node.location.keyword.end_pos).to eq(10..23)
    end

    it "elsif node has no end location" do
      if_node = processed_source.ast
      elsif_node = if_node.else_branch

      expect(elsif_node.location.end).to be_nil
    end
  end

  describe "ERB multi-level elsif range adjustment" do
    let(:erb_source) { "<% if a %><% elsif b %><% elsif c %><% else %><% end %>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        tags: conversion_result.tags
      )
    end

    it "adjusts all elsif keywords to include full ERB tags" do
      if_node = processed_source.ast
      elsif1 = if_node.else_branch
      elsif2 = elsif1.else_branch

      # First elsif: "<% elsif b %>" (positions 10-23)
      expect(elsif1.location.keyword.begin_pos..elsif1.location.keyword.end_pos).to eq(10..23)

      # Second elsif: "<% elsif c %>" (positions 23-36)
      expect(elsif2.location.keyword.begin_pos..elsif2.location.keyword.end_pos).to eq(23..36)
    end
  end
end
