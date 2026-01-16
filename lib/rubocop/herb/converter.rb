# frozen_string_literal: true

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

      # @rbs source: String
      def convert(source) #: String?
        @source = Source.new(source)
        @parse_result = ::Herb.parse(source)

        return nil if parse_result.errors.any?

        build_ruby_code
      end

      private

      def build_ruby_code #: String
        collector = ErbNodeCollector.new
        parse_result.visit(collector)

        buffer = bleach_code(source.code)
        collector.filtered_nodes.each do |node|
          render_node(buffer, node)
        end

        buffer.pack("C*").force_encoding(source.encoding)
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ::Herb::AST::Node
      def render_node(buffer, node) #: void
        if comment_node?(node)
          render_comment_node(buffer, node)
        else
          render_code_node(buffer, node)
        end
      end

      # @rbs node: ::Herb::AST::Node
      def comment_node?(node) #: bool
        node.tag_opening.value == "<%#"
      end

      # @rbs buffer: Array[Integer]
      # @rbs node: ::Herb::AST::Node
      def render_comment_node(buffer, node) #: void
        # Write '#' at the position of '#' in '<%#'
        hash_pos = node.tag_opening.range.to - 1
        buffer[hash_pos] = HASH

        # Write comment content with '#' at the beginning of each line
        ruby_code = ruby_code_for(node)
        from, _to = byte_location_for(node)
        hash_column = node.tag_opening.location.start.column + 2
        formatted_code = format_multiline_comment(ruby_code, hash_column)
        buffer[from, formatted_code.bytesize] = formatted_code.bytes
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
      def render_code_node(buffer, node) #: void
        ruby_code = ruby_code_for(node)
        from, to = byte_location_for(node)
        buffer[from, ruby_code.bytesize] = ruby_code.bytes

        trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
        semicolon_pos = to - trailing_spaces
        buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size

        render_output_marker(buffer, node) if output_node?(node)
      end

      # @rbs node: ::Herb::AST::Node
      def output_node?(node) #: bool
        node.tag_opening.value == "<%="
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
        start = node.content.location.start
        end_ = node.content.location.end
        source.slice(start.line, start.column, end_.line, end_.column)
      end

      # @rbs node: ::Herb::AST::Node
      def byte_location_for(node) #: [Integer, Integer]
        start = node.content.location.start
        end_ = node.content.location.end
        source.byte_range(start.line, start.column, end_.line, end_.column)
      end
    end
  end
end
