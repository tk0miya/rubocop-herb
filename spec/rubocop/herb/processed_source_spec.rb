# frozen_string_literal: true

RSpec.describe RuboCop::Herb::ProcessedSource do
  describe "HTML AST restoration" do
    let(:erb_source) { "<div><%= @name %></div>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert(erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.code, 3.3, "test.html.erb",
        source: conversion_result.source,
        html_tags: conversion_result.html_tags
      )
    end

    def find_send_nodes(node)
      result = []
      return result unless node.is_a?(AST::Node)

      result << node if node.type == :send
      node.children.each { |child| result.concat(find_send_nodes(child)) }
      result
    end

    it "restores original HTML source for open tags" do
      send_nodes = find_send_nodes(processed_source.ast)
      div_node = send_nodes.find { |n| n.children[1] == :div }
      expect(div_node.source).to eq("<div>")
    end

    it "restores original HTML source for close tags" do
      send_nodes = find_send_nodes(processed_source.ast)
      div0_node = send_nodes.find { |n| n.children[1] == :div0 }
      expect(div0_node.source).to eq("</div>")
    end

    it "returns RuboCop AST Node" do
      expect(processed_source.ast).to be_a(RuboCop::AST::Node)
    end

    it "preserves AST structure" do
      expect(processed_source.ast.type).to eq(:begin)
    end
  end

  describe "with multiple HTML tags" do
    let(:erb_source) { "<ul><li><%= item %></li></ul>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert(erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.code, 3.3, "test.html.erb",
        source: conversion_result.source,
        html_tags: conversion_result.html_tags
      )
    end

    def find_send_nodes(node)
      result = []
      return result unless node.is_a?(AST::Node)

      result << node if node.type == :send
      node.children.each { |child| result.concat(find_send_nodes(child)) }
      result
    end

    it "restores all HTML tags" do
      send_nodes = find_send_nodes(processed_source.ast)
      sources = send_nodes.map(&:source)
      expect(sources).to include("<ul>", "<li>", "</li>", "</ul>")
    end
  end

  describe "with attributes" do
    let(:erb_source) { '<div class="container"><%= content %></div>' }
    let(:conversion_result) { RuboCop::Herb::Converter.new(html_visualization: true).convert(erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.code, 3.3, "test.html.erb",
        source: conversion_result.source,
        html_tags: conversion_result.html_tags
      )
    end

    def find_send_nodes(node)
      result = []
      return result unless node.is_a?(AST::Node)

      result << node if node.type == :send
      node.children.each { |child| result.concat(find_send_nodes(child)) }
      result
    end

    it "restores full HTML tag including attributes" do
      send_nodes = find_send_nodes(processed_source.ast)
      div_node = send_nodes.find { |n| n.children[1] == :div }
      expect(div_node.source).to eq('<div class="container">')
    end
  end

  describe "without html_tags" do
    let(:erb_source) { "<div><%= @name %></div>" }
    let(:source) { RuboCop::Herb::Source.new(erb_source) }
    let(:processed_source) do
      described_class.new("div; @name; div0; ", 3.3, "test.html.erb", source:, html_tags: {})
    end

    it "keeps original AST unchanged" do
      expect(processed_source.ast).to be_a(RuboCop::AST::Node)
    end
  end
end
