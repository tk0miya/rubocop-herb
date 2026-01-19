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
end
