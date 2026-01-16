# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    class Converter
      attr_reader :source #: Source
      attr_reader :parse_result #: ::Herb::ParseResult

      LF = 0x0A
      CR = 0x0D
      SPACE = 0x20
      SEMICOLON = 0x3B
      HASH = 0x23
      UNDERSCORE = 0x5F
      EQUALS = 0x3D

      # Node types that indicate the end of a control flow branch
      # Note: ERBEndNode is NOT included because `end` can close both
      # control flow constructs (if/case) and iterator blocks (each/times).
      # For iterators, the block return value is discarded, so we need
      # the _ = marker to avoid Lint/Void warnings.
      BRANCH_BOUNDARY_NODES = [
        ::Herb::AST::ERBElseNode,
        ::Herb::AST::ERBIfNode, # includes elsif
        ::Herb::AST::ERBWhenNode,
        ::Herb::AST::ERBRescueNode,
        ::Herb::AST::ERBEnsureNode,
        ::Herb::AST::ERBInNode
      ].freeze #: Array[class]

      # @rbs source: String
      def convert(source) #: String?
        @source = Source.new(source)
        @parse_result = ::Herb.parse(source)

        # Continue processing even with HTML errors - ERB nodes may still be extractable
        build_ruby_code
      end

      private

      def build_ruby_code #: String
        builder = ErbAstBuilder.new
        erb_nodes = builder.build(parse_result)

        buffer = bleach_code(source.code)
        render_erb_nodes(buffer, filter_comments(erb_nodes), nil)

        buffer.pack("C*").force_encoding(source.encoding)
      end

      # Recursively renders ERB nodes and their children.
      # The parent_next_sibling is passed to handle tail expressions at the end of blocks.
      # @rbs buffer: Array[Integer]
      # @rbs nodes: Array[ErbAst::Node]
      # @rbs parent_next_sibling: ErbAst::Node?
      def render_erb_nodes(buffer, nodes, parent_next_sibling) #: void
        nodes.each_with_index do |node, index|
          next_sibling = nodes[index + 1]
          render_erb_node(buffer, node, next_sibling || parent_next_sibling)
          # Pass the node's next sibling as the parent_next_sibling for its children
          render_erb_nodes(buffer, filter_comments(node.children), next_sibling || parent_next_sibling)
        end
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ErbAst::Node
      # @rbs next_sibling: ErbAst::Node?
      def render_erb_node(buffer, node, next_sibling) #: void
        if node.comment_node?
          render_comment_node(buffer, node.herb_node)
        else
          render_code_node(buffer, node.herb_node, next_sibling&.herb_node)
        end
      end

      # Filters out comments that share the same line with other ERB nodes.
      # @rbs nodes: Array[ErbAst::Node]
      def filter_comments(nodes) #: Array[ErbAst::Node]
        non_comment_start_lines = nodes.reject(&:comment_node?)
                                       .to_set { |node| node.herb_node.location.start.line }

        nodes.reject do |node|
          node.comment_node? && non_comment_start_lines.include?(node.herb_node.location.end.line)
        end
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ::Herb::AST::Node
      def render_comment_node(buffer, node) #: void
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
        # Replace whitespace at hash_column position after newlines with '#'
        # to align '#' at the same column as the first '#' in '<%#'
        # Requires hash_column + 2 spaces to place '#' at the same column (for space after #)
        # If there's not enough whitespace, fall back to replacing the first whitespace
        # If there's no whitespace at all, overwrite the first character with '#'
        # Tab characters are not aligned; just replace the first character with '#'
        result = code.gsub(/(?<=\n)( +)/) do |match|
          if match.length > hash_column + 1
            "#{match[0...hash_column]}##{match[(hash_column + 1)..]}"
          else
            "##{match[1..]}"
          end
        end

        # Handle lines with leading tab or without leading whitespace: overwrite first character with '#'
        # For multibyte characters, pad with spaces to maintain byte size
        result.gsub(/(?<=\n)([^ \n#])/) { "##{" " * (Regexp.last_match(1).bytesize - 1)}" }
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ::Herb::AST::Node
      # @rbs next_node: ::Herb::AST::Node?
      def render_code_node(buffer, node, next_node) #: void # rubocop:disable Metrics/AbcSize
        ruby_code = ruby_code_for(node)
        range = node.content.range
        buffer[range.from, ruby_code.bytesize] = ruby_code.bytes

        trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
        semicolon_pos = range.to - trailing_spaces
        buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size

        # Skip output marker if this is the tail expression of a branch
        # (followed by control keywords like end, else, elsif, etc.)
        # The tail expression's value is used as the branch's return value,
        # so Lint/Void won't trigger and we avoid Style/ConditionalAssignment
        render_output_marker(buffer, node) if output_node?(node) && !tail_of_branch?(next_node)
      end

      # @rbs node: ::Herb::AST::Node
      def output_node?(node) #: bool
        node.tag_opening.value == "<%="
      end

      # @rbs next_node: ::Herb::AST::Node?
      def tail_of_branch?(next_node) #: bool
        return false unless next_node

        BRANCH_BOUNDARY_NODES.any? { |klass| next_node.is_a?(klass) }
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ::Herb::AST::Node
      def render_output_marker(buffer, node) #: void
        # Write '_ =' at the position of '<%=' to make it an assignment
        # This avoids Lint/Void warnings since the expression result is "used"
        pos = node.tag_opening.range.from
        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SPACE
        buffer[pos + 2] = EQUALS
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
