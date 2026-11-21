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
        parse_result: conversion_result.parse_result,
        short_text_ranges: conversion_result.short_text_ranges
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

  describe "short texts" do
    include RuboCop::AST::Sexp

    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        parse_result: conversion_result.parse_result,
        short_text_ranges: conversion_result.short_text_ranges,
        parser_engine:
      )
    end

    def html_nodes(node)
      node.each_node(:send).select { _1.method_name.to_s.include?("__html") }.map do |html|
        range = html.source_range
        [html.method_name, range.begin_pos, range.end_pos, range.line, range.column]
      end
    end

    def tokens(processed_source)
      processed_source.tokens.map { [_1.type, _1.text, _1.begin_pos, _1.end_pos] }
    end

    %i[parser_whitequark parser_prism].each do |engine|
      context "with #{engine}" do
        let(:parser_engine) { engine }

        context "with texts of 1 and 2 characters" do
          let(:erb_source) { "<% if x %>a<% else %>bc<% end %>" }

          it "adds the nodes and the tokens of the texts at their positions, keeping the buffer" do
            expect(processed_source.buffer.source).to eq "   if x;      else;       end;  "
            expect(processed_source.raw_source).to eq "   if x;      else;       end;  "
            expect(processed_source.ast).to eq(
              s(:if, s(:send, nil, :x), s(:send, nil, :_a__html10), s(:send, nil, :_a__html21))
            )
            expect(html_nodes(processed_source.ast)).to eq [[:_a__html10, 10, 11, 1, 10], [:_a__html21, 21, 23, 1, 21]]
            expect(tokens(processed_source)).to eq [
              [:kIF, "if", 3, 5], [:tIDENTIFIER, "x", 6, 7], [:tSEMI, ";", 7, 8],
              [:tIDENTIFIER, "_a", 10, 11],
              [:kELSE, "else", 14, 18], [:tSEMI, ";", 18, 19],
              [:tIDENTIFIER, "_a", 21, 23],
              [:kEND, "end", 26, 29], [:tSEMI, ";", 29, 30]
            ]
            expect(processed_source.diagnostics).to eq []
          end
        end

        context "with texts containing multi-byte characters in multiple lines and a comment" do
          let(:erb_source) { "あ<%= x %>\n🍣<%= y %>\n<%# note %>\n" }

          it "adds the nodes at the positions in characters, and keeps the comment at its position" do
            expect(processed_source.buffer.source).to eq " _ = x;  \n _ = y;  \n  # note   \n"
            expect(html_nodes(processed_source.ast)).to eq [[:_a__html0, 0, 1, 1, 0], [:_a__html10, 10, 11, 2, 0]]
            expect(processed_source.comments.map { [_1.text, _1.location.line, _1.location.column] })
              .to eq [["# note   ", 3, 2]]
          end
        end

        context "with a syntax error after a short text" do
          let(:erb_source) { "a<%= foo( %>b" }

          # The parsers differ in the number of the diagnostics and in the recovery from the error
          it "reports the error at its position in the buffer" do
            expect(processed_source.valid_syntax?).to be false
            expect(processed_source.diagnostics.map { [_1.level, _1.location.begin_pos, _1.location.end_pos] }.uniq)
              .to eq [[:error, 9, 10]]
          end
        end
      end
    end

    context "without short texts" do
      let(:parser_engine) { :default }
      let(:erb_source) { "<% if x %>abc<% end %>" }

      it "parses the buffer" do
        expect(processed_source.ast).to eq s(:if, s(:send, nil, :x), s(:send, nil, :_a__html10), nil)
        expect(tokens(processed_source)).to eq [
          [:kIF, "if", 3, 5], [:tIDENTIFIER, "x", 6, 7], [:tSEMI, ";", 7, 8],
          [:tIDENTIFIER, "_a", 10, 12], [:tSEMI, ";", 12, 13],
          [:kEND, "end", 16, 19], [:tSEMI, ";", 19, 20]
        ]
      end
    end
  end

  describe "#untransformed_node" do
    subject { processed_source.untransformed_node(node) }

    let(:conversion_result) { RuboCop::Herb::Converter.new.convert("test.html.erb", erb_source) }
    let(:processed_source) do
      described_class.new(
        conversion_result.ruby_code, 3.3, "test.html.erb",
        parse_result: conversion_result.parse_result,
        short_text_ranges: conversion_result.short_text_ranges
      )
    end
    let(:erb_source) { "<div><% def foo %><p><%= bar %></p><% end %></div>" }

    context "with the root node" do
      let(:node) { processed_source.ast }

      it "returns the root node before the transformation" do
        expect(collect_method_names(subject)).to eq(%i[div p bar p div])
      end
    end

    context "with a node in the transformed AST" do
      let(:node) { processed_source.ast.each_descendant(:def).first }

      it "returns the node at the same place before the transformation" do
        expect(subject.type).to eq :def
        expect(subject.source_range).to eq node.source_range
        expect(collect_method_names(subject)).to eq(%i[p bar p])
      end
    end

    context "with short texts" do
      let(:erb_source) { "a<% def foo %>b<p><%= bar %></p><% end %>c" }

      context "with the root node" do
        let(:node) { processed_source.ast }

        it "returns the root node of the AST of the buffer, which has no nodes of the short texts" do
          expect(collect_method_names(node)).to eq(%i[_a__html0 _a__html14 p__html15 bar p__html28 _a__html41])
          expect(subject.type).to eq :def
          expect(collect_method_names(subject)).to eq(%i[p bar p])
        end
      end

      context "with a node in the transformed AST" do
        let(:node) { processed_source.ast.each_descendant(:def).first }

        it "returns the node at the same range in the AST of the buffer" do
          expect(collect_method_names(node)).to eq(%i[_a__html14 p__html15 bar p__html28])
          expect(subject.type).to eq :def
          expect([subject.source_range.begin_pos, subject.source_range.end_pos])
            .to eq [node.source_range.begin_pos, node.source_range.end_pos]
          expect(collect_method_names(subject)).to eq(%i[p bar p])
        end
      end
    end

    context "with a node not in the transformed AST" do
      let(:node) { RuboCop::AST::ProcessedSource.new("div", 3.3).ast }

      it { is_expected.to be_nil }
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
      expect(subject.disabled_cops).to eq({ "Style/StringLiterals" => [1..1] })
    end
  end
end
