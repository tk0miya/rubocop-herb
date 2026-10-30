# frozen_string_literal: true

RSpec.describe RuboCop::Herb::ProcessedSource do
  def collect_method_names(node)
    names = []
    return names unless node.respond_to?(:type)

    names << node.method_name if node.type == :send
    node.children.each { names.concat(collect_method_names(_1)) }
    names
  end

  describe "AST transformation" do
    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        parse_result: conversion_result.parse_result
      )
    end

    context "with HTML tags" do
      let(:erb_source) { "<ul><li><%= item %></li></ul>" }

      it "renames the methods rendered from HTML uniquely per position" do
        expect(processed_source.ast).to be_a(RuboCop::AST::Node)
        expect(collect_method_names(processed_source.ast)).to eq(%i[ul__html0 li__html4 item li__html19 ul__html24])
      end
    end
  end

  describe "#comment_config" do
    subject { processed_source.comment_config }

    let(:erb_source) { "<%= @name %>" }
    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:parse_result) { conversion_result.parse_result.with(disabled_cops: { "Style/StringLiterals" => [1..1] }) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        parse_result:
      )
    end

    it "returns a CommentConfig with the disabled cops of the parse result" do
      expect(subject).to be_a(RuboCop::Herb::CommentConfig)
      expect(subject.disabled_cops).to eq({
                                            "Style/StringLiterals" => [1..1],
                                            "Layout/TrailingWhitespace" => [1..1]
                                          })
    end
  end
end
