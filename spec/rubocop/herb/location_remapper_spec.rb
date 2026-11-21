# frozen_string_literal: true

require "parser/current"

RSpec.describe RuboCop::Herb::LocationRemapper do
  let(:remapper) { described_class.new(buffer, expanded_code) }
  let(:buffer) { Parser::Source::Buffer.new("test.html.erb", 1, source: ruby_code) }
  let(:expanded_code) { RuboCop::Herb::ExpandedCode.new(ruby_code, short_text_ranges) }
  let(:expanded_buffer) { Parser::Source::Buffer.new("test.html.erb", 1, source: expanded_code.code) }
  let(:parser) { Parser::CurrentRuby.new.tap { _1.diagnostics.all_errors_are_fatal = false } }
  let(:parsed) { parser.tokenize(expanded_buffer, true) }
  # source: "あ<% if x %>a<% else %>bc<% end %> <%# note %>"
  let(:ruby_code) { "    if x;      else;       end;     # note   " }
  let(:short_text_ranges) { [range(0, 1), range(11, 12), range(22, 24)] }

  def range(from, to)
    RuboCop::Herb::CharRange.new(from:, to:)
  end

  def positions(range)
    [range.begin_pos, range.end_pos]
  end

  def each_node(node, &block)
    block.call(node)
    node.children.grep(Parser::AST::Node).each { each_node(_1, &block) }
  end

  def source_buffers(node)
    buffers = []
    each_node(node) { buffers << _1.location.expression.source_buffer }
    buffers.uniq
  end

  describe "#remap_node" do
    subject(:node) { remapper.remap_node(parsed[0]) }

    it "keeps the structure of the AST, and moves the locations onto the buffer" do
      expect(node).to eq parsed[0]
      expect(source_buffers(node)).to eq [buffer]

      short_text, conditional = node.children
      expect(positions(short_text.location.expression)).to eq [0, 1]
      expect(positions(conditional.location.expression)).to eq [4, 30]
      expect(positions(conditional.loc.keyword)).to eq [4, 6]
      expect(positions(conditional.loc.else)).to eq [15, 19]
      expect(positions(conditional.loc.end)).to eq [27, 30]
      expect(conditional.children.map { positions(_1.location.expression) }).to eq [[7, 8], [11, 12], [22, 24]]
    end
  end

  describe "#remap_comments" do
    subject(:comments) { remapper.remap_comments(parsed[1]) }

    it "moves the comments onto the buffer" do
      expect(comments.map { [_1.text, _1.location.expression.source_buffer, positions(_1.location.expression)] })
        .to eq [["# note   ", buffer, [36, 45]]]
    end
  end

  describe "#remap_tokens" do
    subject(:tokens) { remapper.remap_tokens(parsed[2]) }

    it "moves the tokens onto the buffer, and drops the semicolons of the markers" do
      expect(tokens.map { |type, (value, range)| [type, value, range.source_buffer, positions(range)] }).to eq [
        [:tIDENTIFIER, "_a", buffer, [0, 1]],
        [:kIF, "if", buffer, [4, 6]],
        [:tIDENTIFIER, "x", buffer, [7, 8]],
        [:tSEMI, ";", buffer, [8, 9]],
        [:tIDENTIFIER, "_a", buffer, [11, 12]],
        [:kELSE, "else", buffer, [15, 19]],
        [:tSEMI, ";", buffer, [19, 20]],
        [:tIDENTIFIER, "_a", buffer, [22, 24]],
        [:kEND, "end", buffer, [27, 30]],
        [:tSEMI, ";", buffer, [30, 31]],
        [:tCOMMENT, "# note   ", buffer, [36, 45]]
      ]
    end
  end

  describe "#remap_diagnostic" do
    subject(:diagnostic) { remapper.remap_diagnostic(original) }

    let(:original) do
      Parser::Diagnostic.new(
        :error, :unexpected_token, { token: "kELSE" },
        Parser::Source::Range.new(expanded_buffer, 19, 23),
        [Parser::Source::Range.new(expanded_buffer, 13, 15)]
      )
    end

    it "moves the location and the highlights onto the buffer" do
      expect([diagnostic.level, diagnostic.reason, diagnostic.arguments])
        .to eq [:error, :unexpected_token, { token: "kELSE" }]
      expect([diagnostic.location.source_buffer, positions(diagnostic.location)]).to eq [buffer, [15, 19]]
      expect(diagnostic.highlights.map { [_1.source_buffer, positions(_1)] }).to eq [[buffer, [11, 12]]]
      expect(diagnostic).to be_frozen
    end

    context "with a diagnostic of a subclass with its own message" do
      let(:diagnostic_class) do
        Class.new(Parser::Diagnostic) do
          def initialize(message, location)
            @message = message
            super(:error, :custom, {}, location, [])
          end

          attr_reader :message
        end
      end
      let(:original) { diagnostic_class.new("unexpected else", Parser::Source::Range.new(expanded_buffer, 19, 23)) }

      it "keeps the class and the message" do
        expect(diagnostic).to be_a(diagnostic_class)
        expect(diagnostic.message).to eq "unexpected else"
        expect([diagnostic.location.source_buffer, positions(diagnostic.location)]).to eq [buffer, [15, 19]]
      end
    end
  end
end
