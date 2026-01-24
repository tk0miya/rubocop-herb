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
        parse_result: conversion_result.parse_result
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
        parse_result: conversion_result.parse_result
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
        parse_result: conversion_result.parse_result
      )
    end

    # When brace notation is used (tag has attributes), the closing tag becomes "}"
    # which is part of the block syntax, not a separate send node
    it "restores full HTML tag including attributes" do
      sources = collect_send_sources(processed_source.ast)
      expect(sources).to eq(['<div class="container">', "content"])
    end
  end

  describe "without HTML tags to restore" do
    let(:erb_source) { "<%= @name %>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: false).convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        hybrid_code: conversion_result.hybrid_code,
        parse_result: conversion_result.parse_result
      )
    end

    it "keeps original AST unchanged" do
      expect(processed_source.ast).to be_a(RuboCop::AST::Node)
    end
  end
end
