# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Renders ERB nodes to a buffer using the visitor pattern.
    # Collects comment nodes during traversal and renders them at the end
    # after filtering out comments that share lines with other ERB nodes.
    class ErbNodeRenderer < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      LF = 0x0A
      CR = 0x0D
      SPACE = 0x20
      SEMICOLON = 0x3B
      HASH = 0x23
      UNDERSCORE = 0x5F
      EQUALS = 0x3D

      # Node types that indicate the end of a control flow branch
      BRANCH_BOUNDARY_NODES = [
        ::Herb::AST::ERBElseNode,
        ::Herb::AST::ERBIfNode,
        ::Herb::AST::ERBWhenNode,
        ::Herb::AST::ERBRescueNode,
        ::Herb::AST::ERBEnsureNode,
        ::Herb::AST::ERBInNode
      ].freeze #: Array[class]

      # @rbs @buffer: Array[Integer]
      # @rbs @source: Source
      # @rbs @comment_nodes: Array[::Herb::AST::Node]
      # @rbs @non_comment_start_lines: Set[Integer]
      # @rbs @next_sibling: ::Herb::AST::Node?

      attr_reader :buffer #: Array[Integer]
      attr_reader :source #: Source

      # @rbs buffer: Array[Integer]
      # @rbs source: Source
      def initialize(buffer, source) #: void
        @buffer = buffer
        @source = source
        @comment_nodes = []
        @non_comment_start_lines = Set.new
        @next_sibling = nil

        super()
      end

      # Renders ERB nodes to the buffer.
      # @rbs buffer: Array[Integer]
      # @rbs source: Source
      # @rbs nodes: Array[::Herb::AST::Node]
      def self.render(buffer, source, nodes) #: void
        renderer = new(buffer, source)
        renderer.render(nodes)
      end

      # @rbs nodes: Array[::Herb::AST::Node]
      def render(nodes) #: void
        render_nodes(nodes, nil)
        render_filtered_comments
      end

      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        if comment_node?(node)
          @comment_nodes << node
        else
          render_code_node(node)
          @non_comment_start_lines << node.location.start.line
        end
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        subsequent_sibling = node.subsequent || node.end_node
        render_nodes(node.statements, subsequent_sibling || next_sibling)
        render_nodes([node.subsequent].compact, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        render_nodes(node.statements, @next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        else_sibling = node.else_clause || node.end_node
        render_nodes(node.statements, else_sibling || next_sibling)
        render_nodes([node.else_clause].compact, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: void # rubocop:disable Metrics/AbcSize
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        conditions = node.conditions
        conditions.each_with_index do |condition, index|
          condition_next = conditions[index + 1] || node.else_clause || node.end_node
          render_nodes([condition], condition_next || next_sibling)
        end
        render_nodes([node.else_clause].compact, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        render_nodes(node.statements, @next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: void # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        first_clause = node.rescue_clause || node.else_clause || node.ensure_clause || node.end_node
        render_nodes(node.statements, first_clause || next_sibling)
        rescue_next = node.else_clause || node.ensure_clause || node.end_node || next_sibling
        render_nodes([node.rescue_clause].compact, rescue_next)
        render_nodes([node.else_clause].compact, node.ensure_clause || node.end_node || next_sibling)
        render_nodes([node.ensure_clause].compact, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        render_nodes(node.statements, node.subsequent || next_sibling)
        render_nodes([node.subsequent].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        render_nodes(node.statements, @next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        render_nodes(node.body, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        render_nodes(node.statements, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        render_nodes(node.statements, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line

        next_sibling = @next_sibling
        render_nodes(node.statements, node.end_node || next_sibling)
        render_nodes([node.end_node].compact, next_sibling)
      end

      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line
      end

      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: void
        render_code_node(node)
        @non_comment_start_lines << node.location.start.line
      end

      private

      # @rbs nodes: Array[::Herb::AST::Node]
      # @rbs parent_next_sibling: ::Herb::AST::Node?
      def render_nodes(nodes, parent_next_sibling) #: void
        nodes.each_with_index do |node, index|
          next_sibling = nodes[index + 1]
          @next_sibling = next_sibling || parent_next_sibling
          visit(node)
        end
      end

      # Renders comment nodes that don't share lines with other ERB nodes.
      def render_filtered_comments #: void
        @comment_nodes.each do |node|
          next if @non_comment_start_lines.include?(node.location.end.line)

          render_comment_content(node)
        end
      end

      # @rbs node: ::Herb::AST::Node
      def comment_node?(node) #: bool
        node.respond_to?(:tag_opening) && node.tag_opening.value == "<%#"
      end

      # @rbs node: ::Herb::AST::Node
      def render_code_node(node) #: void # rubocop:disable Metrics/AbcSize
        ruby_code = ruby_code_for(node)
        range = node.content.range
        buffer[range.from, ruby_code.bytesize] = ruby_code.bytes

        trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
        semicolon_pos = range.to - trailing_spaces
        buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size

        render_output_marker(node) if output_node?(node) && !tail_of_branch?
      end

      # @rbs node: ::Herb::AST::Node
      def render_comment_content(node) #: void # rubocop:disable Metrics/AbcSize
        # Write '#' at the position of '#' in '<%#'
        hash_pos = node.tag_opening.range.to - 1
        buffer[hash_pos] = HASH

        # Write comment content with '#' at the beginning of each line
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

      # @rbs node: ::Herb::AST::Node
      def output_node?(node) #: bool
        node.respond_to?(:tag_opening) && node.tag_opening.value == "<%="
      end

      def tail_of_branch? #: bool
        return false unless @next_sibling

        BRANCH_BOUNDARY_NODES.any? { |klass| @next_sibling.is_a?(klass) }
      end

      # @rbs node: ::Herb::AST::Node
      def render_output_marker(node) #: void
        pos = node.tag_opening.range.from
        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SPACE
        buffer[pos + 2] = EQUALS
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String
        source.byteslice(node.content.range)
      end
    end
  end
end
