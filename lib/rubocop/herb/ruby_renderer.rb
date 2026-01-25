# frozen_string_literal: true

require "forwardable"
require "herb"
require_relative "node_range"

module RuboCop
  module Herb
    # Visitor-based renderer that traverses Herb AST and renders Ruby code.
    # Comments are retrieved from ParseResult and rendered at the end
    # with filtering applied.
    class RubyRenderer < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      extend Forwardable
      include Characters

      # Render ERB source to Ruby code
      # @rbs parse_result: ParseResult
      # @rbs html_visualization: bool
      def self.render(parse_result, html_visualization: false) #: String
        renderer = new(parse_result, html_visualization:)
        parse_result.ast.visit(renderer)
        renderer.code
      end

      attr_reader :buffer #: Array[String]
      attr_reader :parse_result #: ParseResult
      attr_reader :code #: String
      attr_reader :tag_counter #: Integer
      attr_reader :html_visualization #: bool

      # @rbs!
      #   def source_encoding: () -> Encoding
      #   def erb_locations: () -> Hash[Integer, ErbLocation]
      #   def erb_max_columns: () -> Hash[Integer, Integer]
      #   def erb_comment_nodes: () -> Array[::Herb::AST::ERBContentNode]
      #   def byteslice: (::Herb::Range | ::Herb::Location) -> String
      #   def location_to_range: (::Herb::Location) -> ::Herb::Range
      #   def tail_expression?: (::Herb::AST::Node) -> bool
      #   def byte_to_char_pos: (Integer byte_pos) -> Integer
      def_delegator :parse_result, :encoding, :source_encoding
      def_delegators :parse_result, :erb_locations, :erb_max_columns, :erb_comment_nodes,
                     :byteslice, :location_to_range, :tail_expression?, :byte_to_char_pos

      # @rbs parse_result: ParseResult
      # @rbs html_visualization: bool
      def initialize(parse_result, html_visualization: false) #: void
        @parse_result = parse_result
        @buffer = bleach_code(parse_result.code)
        @tag_counter = 0
        @html_visualization = html_visualization

        super()
      end

      # Override to render comments and build code after document traversal completes
      # @rbs node: ::Herb::AST::DocumentNode
      def visit_document_node(node) #: void
        super
        render_comments
        @code = buffer.join
      end

      # @rbs!
      #   def visit_erb_block_node: (::Herb::AST::ERBBlockNode node) -> void
      #   def visit_erb_for_node: (::Herb::AST::ERBForNode node) -> void
      #   def visit_erb_while_node: (::Herb::AST::ERBWhileNode node) -> void
      #   def visit_erb_until_node: (::Herb::AST::ERBUntilNode node) -> void
      #   def visit_erb_if_node: (::Herb::AST::ERBIfNode node) -> void
      #   def visit_erb_unless_node: (::Herb::AST::ERBUnlessNode node) -> void
      #   def visit_erb_else_node: (::Herb::AST::ERBElseNode node) -> void
      #   def visit_erb_when_node: (::Herb::AST::ERBWhenNode node) -> void
      #   def visit_erb_begin_node: (::Herb::AST::ERBBeginNode node) -> void
      #   def visit_erb_rescue_node: (::Herb::AST::ERBRescueNode node) -> void
      #   def visit_erb_ensure_node: (::Herb::AST::ERBEnsureNode node) -> void
      #   def visit_erb_case_node: (::Herb::AST::ERBCaseNode node) -> void
      #   def visit_erb_yield_node: (::Herb::AST::ERBYieldNode node) -> void
      #   def visit_erb_end_node: (::Herb::AST::ERBEndNode node) -> void

      # Define visit methods for ERB nodes that render code and continue traversal
      %i[block for while until if unless else when begin rescue ensure case yield end].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          render_code_node(node)
          super(node)
        end
      end

      # Visit ERB content nodes (the actual Ruby code: <% %> or <%= %>)
      # Comments are skipped here and rendered later via render_comments
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        render_code_node(node) unless node.tag_opening.value == "<%#"
        super
      end

      # Visit HTML element nodes (container for open tag, content, and close tag)
      # If the element contains ERB nodes, renders open tag with semicolon/brace and processes children
      # If the element contains no ERB nodes, renders only the open tag name with full element range
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        return super unless html_visualization

        if contains_erb?(node)
          as_brace = parse_result.html_block_positions.include?(node.open_tag.tag_opening.range.from)
          render_open_tag_node(node.open_tag, as_brace:)
          super
          render_close_tag_node(node.close_tag, as_brace:) if node.close_tag
        else
          render_open_tag_node(node.open_tag, as_brace: false)
        end
      end

      # Visit HTML text nodes (plain text content between tags)
      # Renders underscore at first non-whitespace position to indicate content presence
      # @rbs node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(node) #: void
        render_text_node(node) if html_visualization
        super
      end

      # Visit HTML comment nodes (<!-- ... -->)
      # Comments containing ERB are processed normally (super visits children)
      # Pure HTML comments are rendered as "__;" to indicate content presence (like text nodes)
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def visit_html_comment_node(node) #: void
        if contains_erb?(node)
          super
        elsif html_visualization
          render_html_comment_node(node)
        end
        # When html_visualization is disabled and no ERB, comment is bleached (all spaces)
      end

      private

      # @rbs node: ::Herb::AST::ERBContentNode
      def output_node?(node) #: bool
        node.tag_opening.value == "<%="
      end

      # @rbs node: ::Herb::AST::Node
      def render_code_node(node) #: void # rubocop:disable Metrics/AbcSize
        return unless node.respond_to?(:content) && node.content

        ruby_code = ruby_code_for(node)
        range = node.content.range
        char_from = byte_to_char_pos(range.from)
        buffer[char_from, ruby_code.length] = ruby_code.chars

        trailing_spaces = ruby_code.length - ruby_code.rstrip.length
        semicolon_char_pos = byte_to_char_pos(range.to) - trailing_spaces
        buffer[semicolon_char_pos] = CHAR_SEMICOLON if semicolon_char_pos < buffer.size

        render_output_marker(node) if output_node?(node) && needs_output_marker?(node)
      end

      # Check if output node needs _ = marker
      # When html_visualization is disabled, always add marker to avoid Lint/Void false positives
      # When enabled, only add marker if not a tail expression
      # @rbs node: ::Herb::AST::Node
      def needs_output_marker?(node) #: bool
        return true unless html_visualization

        !tail_expression?(node)
      end

      # @rbs node: ::Herb::AST::Node
      def render_output_marker(node) #: void
        char_pos = byte_to_char_pos(node.tag_opening.range.from)
        buffer[char_pos] = CHAR_UNDERSCORE
        buffer[char_pos + 1] = CHAR_SPACE
        buffer[char_pos + 2] = CHAR_EQUALS
      end

      # Render HTML open tag as Ruby code
      # When as_brace is true, uses brace notation: "div { "
      # Otherwise, uses semicolon notation: "div; "
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      # @rbs as_brace: bool
      def render_open_tag_node(node, as_brace:) #: void
        tag_name = node.tag_name.value
        ruby_code = as_brace ? "#{tag_name} { " : "#{tag_name}; "

        char_pos = byte_to_char_pos(node.tag_opening.range.from)
        buffer[char_pos, ruby_code.length] = ruby_code.chars
      end

      # Render HTML close tag as Ruby code
      # When as_brace is true, renders "};" to ensure valid Ruby after block
      # Otherwise, renders "tagN; " with counter to distinguish closing tags
      # @rbs node: ::Herb::AST::HTMLCloseTagNode
      # @rbs as_brace: bool
      def render_close_tag_node(node, as_brace:) #: void
        char_pos = byte_to_char_pos(node.tag_opening.range.from)

        if as_brace
          buffer[char_pos] = CHAR_RIGHT_BRACE
          buffer[char_pos + 1] = CHAR_SEMICOLON
        else
          tag_name = node.tag_name.value
          ruby_code = "#{tag_name}#{next_tag_counter}; "
          buffer[char_pos, ruby_code.length] = ruby_code.chars
        end
      end

      # Render HTML text node by placing "_N;" at first non-whitespace position
      # This indicates content presence to avoid Lint/EmptyBlock and similar cops
      # Uses "_N" with counter to avoid false positives from Style/IdenticalConditionalBranches
      # Requires at least 4 characters from the first non-whitespace position to end
      # @rbs node: ::Herb::AST::HTMLTextNode
      def render_text_node(node) #: void
        range = NodeRange.compute(node, parse_result)
        text = byteslice(range)
        match = text.match(/\S/)
        return unless match

        char_from = byte_to_char_pos(range.from)
        char_to = byte_to_char_pos(range.to)
        char_pos = char_from + match.begin(0)
        return unless char_pos + 4 <= char_to

        render_tag_marker(char_pos)
      end

      # Render collected comments that can be safely converted to Ruby comments
      def render_comments #: void
        erb_comment_nodes.each do |node|
          render_erb_comment_node(node) if renderable_comment?(node)
        end
      end

      # Check if this comment can be rendered as a Ruby comment without breaking code
      # Comments are not renderable when there's code to the right on the same line,
      # because Ruby's # comment extends to end of line and would comment out the code
      # @rbs node: ::Herb::AST::ERBContentNode
      def renderable_comment?(node) #: bool
        line = node.location.end.line
        return true unless erb_max_columns.key?(line)

        node.location.start.column >= erb_max_columns[line]
      end

      # @rbs node: ::Herb::AST::ERBContentNode
      def render_erb_comment_node(node) #: void # rubocop:disable Metrics/AbcSize
        hash_char_pos = byte_to_char_pos(node.tag_opening.range.to - 1)
        buffer[hash_char_pos] = CHAR_HASH

        ruby_code = ruby_code_for(node)
        range = node.content.range
        hash_column = node.tag_opening.location.start.column + 2
        formatted_code = format_multiline_comment(ruby_code, hash_column)
        char_from = byte_to_char_pos(range.from)
        buffer[char_from, formatted_code.length] = formatted_code.chars
      end

      # Render HTML comment as "_N;" to indicate content presence (like text nodes)
      # Places "_N;" at the start of the comment with counter
      # Uses "_N" with counter to avoid false positives from Style/IdenticalConditionalBranches
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def render_html_comment_node(node) #: void
        char_pos = byte_to_char_pos(node.comment_start.range.from)
        render_tag_marker(char_pos)
      end

      # Render tag marker "_x;" at the given character position and increment counter
      # Uses alphabetic markers (_a, _b, ... _z) to avoid conflict with Ruby's numbered parameters (_1, _2, etc.)
      # @rbs char_pos: Integer -- character position in buffer
      def render_tag_marker(char_pos) #: void
        buffer[char_pos] = CHAR_UNDERSCORE
        buffer[char_pos + 1] = (LOWERCASE_A + next_tag_counter).chr
        buffer[char_pos + 2] = CHAR_SEMICOLON
      end

      # Increment tag counter and return new value (cycles through 0-9)
      def next_tag_counter #: Integer
        @tag_counter = tag_counter.succ % 10
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

        result.gsub(/(?<=\n)([^ \n#])/) { "##{" " * (Regexp.last_match(1).length - 1)}" }
      end

      # Convert source code to array of characters, replacing non-newline characters with spaces
      # @rbs code: String
      def bleach_code(code) #: Array[String]
        code.chars.map do |char|
          case char
          when CHAR_LF, CHAR_CR
            char
          else
            CHAR_SPACE
          end
        end
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String
        byteslice(node.content.range)
      end

      # Check if an HTML node contains ERB
      # @rbs node: html_node
      def contains_erb?(node) #: bool
        parse_result.contains_erb?(NodeRange.compute(node, parse_result))
      end
    end
  end
end
