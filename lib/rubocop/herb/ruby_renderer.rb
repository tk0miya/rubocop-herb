# frozen_string_literal: true

require "herb"
require_relative "ruby_renderer/block_context"

module RuboCop
  module Herb
    # Result of rendering ERB to Ruby
    RenderResult = Struct.new(:ruby_code, :html_tag_mappings, :erb_end_mappings, keyword_init: true)

    # Visitor-based renderer that traverses Herb AST and renders Ruby code.
    # Comments are collected during traversal and rendered at the end
    # with filtering applied.
    class RubyRenderer < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      include Characters

      # Render ERB source to Ruby code
      # @rbs source: Source
      # @rbs html_visualization: bool
      def self.render(source, html_visualization: false) #: RenderResult
        renderer = new(source, html_visualization:)
        source.parse_result.visit(renderer)
        RenderResult.new(
          ruby_code: renderer.result,
          html_tag_mappings: renderer.html_tag_mappings,
          erb_end_mappings: renderer.erb_end_mappings
        )
      end

      attr_reader :buffer #: Array[Integer]
      attr_reader :source #: Source
      attr_reader :result #: String
      attr_reader :block_stack #: Array[BlockContext]
      attr_reader :comment_nodes #: Array[::Herb::AST::Node]
      attr_reader :code_positions #: Hash[Integer, Integer]
      attr_reader :close_tag_counter #: Integer
      attr_reader :html_visualization #: bool
      attr_reader :html_tag_mappings #: Array[{from: Integer, to: Integer, original: String, html_end: Integer}]
      attr_reader :erb_end_mappings #: Array[{from: Integer, to: Integer, erb_end: Integer}]

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
        @html_tag_mappings = []
        @erb_end_mappings = []

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
        record_erb_end_mapping(node)
        super
      end

      # Visit HTML element nodes to render opening tags as method calls
      # Always renders opening tag for AST source replacement
      # With html_visualization, also renders close tags and processes based on ERB content
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        render_html_open_tag(node)

        return super unless html_visualization

        range = source.location_to_range(node.location)
        if source.contains_erb?(range)
          render_open_tag_node(node.open_tag)
          super
          render_close_tag_node(node.close_tag) if node.close_tag
        else
          render_open_tag_node(node.open_tag)
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

      # Render HTML opening tag as a method call (e.g., <div ...> becomes "div; ")
      # Shifted one character left to avoid leading space warnings
      # @rbs node: ::Herb::AST::HTMLElementNode
      def render_html_open_tag(node) #: void
        tag_name = node.tag_name.value
        open_tag = node.open_tag
        # Write tag name starting at the position of '<' (one character left)
        start_pos = open_tag.tag_opening.range.from
        buffer[start_pos, tag_name.bytesize] = tag_name.bytes
        buffer[start_pos + tag_name.bytesize] = SEMICOLON

        # Record mapping for later AST source replacement
        record_html_tag_mapping(tag_name, start_pos, open_tag)
      end

      # @rbs tag_name: String
      # @rbs start_pos: Integer
      # @rbs open_tag: ::Herb::AST::HTMLOpenTagNode
      def record_html_tag_mapping(tag_name, start_pos, open_tag) #: void
        open_tag_start = open_tag.tag_opening.range.from
        open_tag_end = open_tag.tag_closing.range.to
        original_html = source.code.byteslice(open_tag_start, open_tag_end - open_tag_start)
        html_tag_mappings << {
          from: start_pos,
          to: start_pos + tag_name.bytesize,
          original: original_html,
          html_end: open_tag_end # Original HTML tag end position for autocorrect
        }
      end

      # Record ERB end tag mapping for extending control flow node ranges
      # @rbs node: ::Herb::AST::ERBEndNode
      def record_erb_end_mapping(node) #: void
        content_range = node.content.range
        # Find where 'end' keyword starts in the content (skip leading whitespace)
        end_keyword_start = content_range.from + (node.content.value =~ /end/)
        end_keyword_end = end_keyword_start + 3 # 'end' is 3 bytes
        erb_tag_end = node.tag_closing.range.to

        erb_end_mappings << {
          from: end_keyword_start,
          to: end_keyword_end,
          erb_end: erb_tag_end
        }
      end

      # Render HTML open tag as Ruby code for visualization (e.g., "<p>" -> "p; ")
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
        range = source.location_to_range(node.location)
        match = source.byteslice(range).match(/\S/)
        return unless match

        pos = range.from + match.begin(0)
        return unless pos + 3 <= range.to

        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SEMICOLON
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
    end
  end
end
