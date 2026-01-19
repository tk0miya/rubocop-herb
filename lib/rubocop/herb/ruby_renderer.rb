# frozen_string_literal: true

require "herb"
require_relative "ruby_renderer/block_context"

module RuboCop
  module Herb
    # Visitor-based renderer that traverses Herb AST and renders Ruby code.
    # Comments are collected during traversal and rendered at the end
    # with filtering applied.
    class RubyRenderer < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      include Characters

      # Result of rendering ERB source to Ruby code
      Result = Data.define(
        :source, #: Source
        :code, #: String
        :tags #: Hash[Integer, Tag]
      )

      # Render ERB source to Ruby code
      # @rbs source: Source
      # @rbs html_visualization: bool
      def self.render(source, html_visualization: false) #: Result
        renderer = new(source, html_visualization:)
        source.parse_result.visit(renderer)
        Result.new(source:, code: renderer.result, tags: renderer.tags)
      end

      attr_reader :buffer #: Array[Integer]
      attr_reader :source #: Source
      attr_reader :result #: String
      attr_reader :block_stack #: Array[BlockContext]
      attr_reader :comment_nodes #: Array[::Herb::AST::Node]
      attr_reader :code_positions #: Hash[Integer, Integer]
      attr_reader :close_tag_counter #: Integer
      attr_reader :html_visualization #: bool
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs source: Source
      # @rbs html_visualization: bool
      def initialize(source, html_visualization: false) #: void
        @source = source
        @buffer = bleach_code(source.code)
        @result = ""
        @block_stack = []
        @comment_nodes = []
        @code_positions = {}
        @close_tag_counter = 0
        @html_visualization = html_visualization
        @tags = {}

        super()
      end

      # Override to render comments and build result after document traversal completes
      # @rbs node: ::Herb::AST::DocumentNode
      def visit_document_node(node) #: void
        super
        render_comments
        @result = buffer.pack("C*").force_encoding(source.encoding)
      end

      # Visit ERB block nodes (iterators like each, times, loop)
      # These are NOT control flow - return value is discarded
      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        render_code_node(node)
        push_block(node.body)
        super
        pop_block
      end

      # Visit ERB for nodes (for loops - return value is discarded)
      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: void
        render_code_node(node)
        push_block(node.statements)
        super
        pop_block
      end

      # Visit ERB while nodes (while loops - return value is discarded)
      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: void
        render_code_node(node)
        push_block(node.statements)
        super
        pop_block
      end

      # Visit ERB until nodes (until loops - return value is discarded)
      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: void
        render_code_node(node)
        push_block(node.statements)
        super
        pop_block
      end

      # Visit ERB if nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        render_code_node(node)
        record_erb_tag(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB unless nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        render_code_node(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB else nodes (control flow continuation - returns value)
      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        render_code_node(node)
        record_erb_tag(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB case nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: void
        render_code_node(node)
        super
      end

      # Visit ERB when nodes (control flow continuation - returns value)
      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        render_code_node(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB begin nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: void
        render_code_node(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB rescue nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        render_code_node(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB ensure nodes (control flow - returns value)
      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        render_code_node(node)
        push_block(node.statements, returning_value: true)
        super
        pop_block
      end

      # Visit ERB content nodes (the actual Ruby code: <% %> or <%= %>)
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        if node.tag_opening.value == "<%#"
          comment_nodes << node
        else
          render_code_node(node)
        end
        super
      end

      # Visit ERB end nodes
      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: void
        render_code_node(node)
        record_erb_tag(node)
        super
      end

      # Visit HTML element nodes (container for open tag, content, and close tag)
      # If the element contains ERB nodes, renders open tag with semicolon and processes children
      # If the element contains no ERB nodes, renders only the open tag name with full element range
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        return super unless html_visualization

        element_range = compute_node_range(node)
        render_open_tag_node(node.open_tag)

        if source.contains_erb?(element_range)
          record_tag_info(node.open_tag)
          super
          if node.close_tag
            render_close_tag_node(node.close_tag)
            record_tag_info(node.close_tag)
          end
        else
          record_tag_info(node)
        end
      end

      # Visit HTML text nodes (plain text content between tags)
      # Renders underscore at first non-whitespace position to indicate content presence
      # @rbs node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(node) #: void
        render_text_node(node) if html_visualization
        super
      end

      private

      # @rbs statements: Array[::Herb::AST::Node]
      # @rbs returning_value: bool
      def push_block(statements, returning_value: false) #: void
        block_stack.push(BlockContext.new(statements, returning_value:))
      end

      def pop_block #: void
        block_stack.pop
      end

      def current_block #: BlockContext?
        block_stack.last
      end

      # @rbs node: ::Herb::AST::ERBContentNode
      def output_node?(node) #: bool
        node.tag_opening.value == "<%="
      end

      # Check if this output node is a tail expression that doesn't need _ = marker
      # @rbs node: ::Herb::AST::ERBContentNode
      def tail_expression?(node) #: bool
        return false unless current_block
        return false unless current_block.returning_value
        return false unless current_block.last_statement?(node)

        true
      end

      # @rbs node: ::Herb::AST::Node
      def render_code_node(node) #: void # rubocop:disable Metrics/AbcSize
        return unless node.respond_to?(:content) && node.content

        record_code_position(node)

        ruby_code = ruby_code_for(node)
        range = node.content.range
        buffer[range.from, ruby_code.bytesize] = ruby_code.bytes

        trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
        semicolon_pos = range.to - trailing_spaces
        buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size

        render_output_marker(node) if output_node?(node) && !tail_expression?(node)
      end

      # Record line and column for comment filtering (keep maximum column per line)
      # @rbs node: ::Herb::AST::Node
      def record_code_position(node) #: void
        line = node.location.start.line
        column = node.location.start.column
        code_positions[line] = column if !code_positions.key?(line) || code_positions[line] < column
      end

      # @rbs node: ::Herb::AST::Node
      def render_output_marker(node) #: void
        pos = node.tag_opening.range.from
        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SPACE
        buffer[pos + 2] = EQUALS
      end

      # Get the byte range of a node
      # @rbs node: ::Herb::AST::HTMLElementNode | ::Herb::AST::HTMLTextNode
      #          | ::Herb::AST::HTMLOpenTagNode | ::Herb::AST::HTMLCloseTagNode
      #          | ::Herb::AST::ERBIfNode | ::Herb::AST::ERBElseNode | ::Herb::AST::ERBEndNode
      def compute_node_range(node) #: ::Herb::Range # rubocop:disable Metrics/AbcSize
        case node
        when ::Herb::AST::HTMLElementNode
          from = node.open_tag.tag_opening.range.from
          to = node.close_tag ? node.close_tag.tag_closing.range.to : node.open_tag.tag_closing.range.to
          ::Herb::Range.new(from, to)
        when ::Herb::AST::HTMLTextNode
          source.location_to_range(node.location)
        when ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode,
             ::Herb::AST::ERBIfNode, ::Herb::AST::ERBElseNode, ::Herb::AST::ERBEndNode
          ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        end
      end

      # Compute the position of the keyword in ERB content (skipping leading whitespace)
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBElseNode | ::Herb::AST::ERBEndNode
      def compute_erb_keyword_position(node) #: Integer
        content = source.byteslice(node.content.range)
        leading_spaces = content.match(/\A\s*/)[0].bytesize
        node.content.range.from + leading_spaces
      end

      # Render HTML open tag as Ruby code (e.g., "<div>" -> "div; ")
      # Attributes are ignored, only the tag name is rendered
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def render_open_tag_node(node) #: void
        tag_name = node.tag_name.value
        ruby_code = "#{tag_name}; "

        start_pos = node.tag_opening.range.from
        buffer[start_pos, ruby_code.bytesize] = ruby_code.bytes
      end

      # Render HTML close tag as Ruby code (e.g., "</p>" -> "p1; ")
      # Maintains byte length: "</" (2) + tag_name + ">" (1) = tag_name + counter (1) + "; " (2)
      # @rbs node: ::Herb::AST::HTMLCloseTagNode
      def render_close_tag_node(node) #: void
        tag_name = node.tag_name.value
        ruby_code = "#{tag_name}#{close_tag_counter}; "
        @close_tag_counter = close_tag_counter.succ % 10

        start_pos = node.tag_opening.range.from
        buffer[start_pos, ruby_code.bytesize] = ruby_code.bytes
      end

      # Render HTML text node by placing "_; " at first non-whitespace position
      # This indicates content presence to avoid Lint/EmptyBlock and similar cops
      # Requires at least 3 bytes from the first non-whitespace position to end
      # @rbs node: ::Herb::AST::HTMLTextNode
      def render_text_node(node) #: void
        range = compute_node_range(node)
        match = source.byteslice(range).match(/\S/)
        return unless match

        pos = range.from + match.begin(0)
        return unless pos + 3 <= range.to

        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SEMICOLON

        record_tag_info(node)
      end

      # Render collected comments that can be safely converted to Ruby comments
      def render_comments #: void
        comment_nodes.each do |node|
          render_comment_node(node) if renderable_comment?(node)
        end
      end

      # Check if this comment can be rendered as a Ruby comment without breaking code
      # Comments are not renderable when there's code to the right on the same line,
      # because Ruby's # comment extends to end of line and would comment out the code
      # @rbs node: ::Herb::AST::ERBContentNode
      def renderable_comment?(node) #: bool
        line = node.location.end.line
        return true unless code_positions.key?(line)

        node.location.start.column >= code_positions[line]
      end

      # @rbs node: ::Herb::AST::ERBContentNode
      def render_comment_node(node) #: void # rubocop:disable Metrics/AbcSize
        hash_pos = node.tag_opening.range.to - 1
        buffer[hash_pos] = HASH

        ruby_code = ruby_code_for(node)
        range = node.content.range
        hash_column = node.tag_opening.location.start.column + 2
        formatted_code = format_multiline_comment(ruby_code, hash_column)
        buffer[range.from, formatted_code.bytesize] = formatted_code.bytes
      end

      # @rbs code: String
      # @rbs hash_column: Integer
      def format_multiline_comment(code, hash_column) #: String
        result = code.gsub(/(?<=\n)( +)/) do |match|
          if match.length > hash_column + 1
            "#{match[0...hash_column]}##{match[(hash_column + 1)..]}"
          else
            "##{match[1..]}"
          end
        end

        result.gsub(/(?<=\n)([^ \n#])/) { "##{" " * (Regexp.last_match(1).bytesize - 1)}" }
      end

      # @rbs code: String
      def bleach_code(code) #: Array[Integer]
        code.bytes.map do |byte|
          case byte
          when LF, CR
            byte
          else
            SPACE
          end
        end
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String
        source.byteslice(node.content.range)
      end

      # Record tag info for AST restoration
      # @rbs node: ::Herb::AST::HTMLElementNode | ::Herb::AST::HTMLOpenTagNode | ::Herb::AST::HTMLCloseTagNode | ::Herb::AST::HTMLTextNode
      def record_tag_info(node) #: void
        range = compute_node_range(node)
        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Record ERB tag info for AST restoration
      # The key is the position of the keyword in the content (skipping leading whitespace)
      # The value is the full ERB tag range (including <% and %>)
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBElseNode | ::Herb::AST::ERBEndNode
      def record_erb_tag(node) #: void
        keyword_pos = compute_erb_keyword_position(node)
        range = compute_node_range(node)
        tags[keyword_pos] = Tag.new(range:, restore_source: false)
      end
    end
  end
end
