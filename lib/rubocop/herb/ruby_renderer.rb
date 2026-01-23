# frozen_string_literal: true

require "forwardable"
require "herb"
require_relative "node_range"
require_relative "ruby_renderer/block_context"

module RuboCop
  module Herb
    # Visitor-based renderer that traverses Herb AST and renders Ruby code.
    # Comments are retrieved from ParseResult and rendered at the end
    # with filtering applied.
    class RubyRenderer < ::Herb::Visitor # rubocop:disable Metrics/ClassLength
      extend Forwardable
      include Characters

      # Result of rendering ERB source to Ruby code
      Result = Data.define(
        :parse_result, #: ParseResult
        :code, #: String
        :tags #: Hash[Integer, Tag]
      )

      # Render ERB source to Ruby code
      # @rbs parse_result: ParseResult
      # @rbs html_visualization: bool
      def self.render(parse_result, html_visualization: false) #: Result
        renderer = new(parse_result, html_visualization:)
        parse_result.ast.visit(renderer)
        renderer.result
      end

      attr_reader :buffer #: Array[Integer]
      attr_reader :parse_result #: ParseResult
      attr_reader :result #: Result
      attr_reader :block_stack #: Array[BlockContext]
      attr_reader :tag_counter #: Integer
      attr_reader :html_visualization #: bool
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs!
      #   def source_encoding: () -> Encoding
      #   def erb_locations: () -> Hash[Integer, ErbLocation]
      #   def erb_max_columns: () -> Hash[Integer, Integer]
      #   def erb_comment_nodes: () -> Array[::Herb::AST::ERBContentNode]
      #   def byteslice: (::Herb::Range) -> String
      #   def location_to_range: (::Herb::Location) -> ::Herb::Range
      def_delegator :parse_result, :encoding, :source_encoding
      def_delegators :parse_result, :erb_locations, :erb_max_columns, :erb_comment_nodes, :byteslice, :location_to_range

      # @rbs parse_result: ParseResult
      # @rbs html_visualization: bool
      def initialize(parse_result, html_visualization: false) #: void
        @parse_result = parse_result
        @buffer = bleach_code(parse_result.code)
        @block_stack = []
        @tag_counter = 0
        @html_visualization = html_visualization
        @tags = {}

        super()
      end

      # Override to render comments and build result after document traversal completes
      # @rbs node: ::Herb::AST::DocumentNode
      def visit_document_node(node) #: void
        super
        render_comments
        all_tags = build_erb_tags.merge(tags)
        code = buffer.pack("C*").force_encoding(source_encoding)
        @result = Result.new(parse_result:, code:, tags: all_tags)
      end

      # @rbs!
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

      # Visit ERB block nodes (iterators like each, times, loop)
      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        render_code_node(node)
        push_block(node.body)
        visit_child_nodes(node)
        pop_block
      end

      # Define visit methods for ERB loop nodes (return value is discarded)
      %i[for while until].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          render_code_node(node)
          push_block(node.statements)
          visit_child_nodes(node)
          pop_block
        end
      end

      # Define visit methods for ERB control flow nodes (returns value)
      %i[if unless else when begin rescue ensure].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          render_code_node(node)
          push_block(node.statements, returning_value: true)
          visit_child_nodes(node)
          pop_block
        end
      end

      # Visit ERB case nodes (control flow without block)
      # @rbs override
      def visit_erb_case_node(node) #: void
        render_code_node(node)
        super
      end

      # Visit ERB content nodes (the actual Ruby code: <% %> or <%= %>)
      # Comments are skipped here and rendered later via render_comments
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        render_code_node(node) unless node.tag_opening.value == "<%#"
        super
      end

      # Visit ERB yield nodes (<%= yield %> or <%= yield(...) %>)
      # @rbs node: ::Herb::AST::ERBYieldNode
      def visit_erb_yield_node(node) #: void
        render_code_node(node)
        super
      end

      # Visit ERB end nodes
      # @rbs node: ::Herb::AST::ERBEndNode
      def visit_erb_end_node(node) #: void
        render_code_node(node)
        super
      end

      # Visit HTML element nodes (container for open tag, content, and close tag)
      # If the element contains ERB nodes, renders open tag with semicolon/brace and processes children
      # If the element contains no ERB nodes, renders only the open tag name with full element range
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void # rubocop:disable Metrics/AbcSize
        return super unless html_visualization

        if contains_erb?(node)
          as_brace = parse_result.html_block_positions.include?(node.open_tag.tag_opening.range.from)
          render_open_tag_node(node.open_tag, as_brace:)
          # Only restore open tag if it doesn't contain ERB (e.g., ERB in attributes)
          # Restoring tags with ERB causes false positives in Layout/SpaceAroundOperators
          record_tag_info(node.open_tag) unless contains_erb?(node.open_tag)
          super
          if node.close_tag
            render_close_tag_node(node.close_tag, as_brace:)
            record_tag_info(node.close_tag)
          end
        else
          render_open_tag_node(node.open_tag, as_brace: false)
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

        ruby_code = ruby_code_for(node)
        range = node.content.range
        buffer[range.from, ruby_code.bytesize] = ruby_code.bytes

        trailing_spaces = ruby_code.bytesize - ruby_code.rstrip.bytesize
        semicolon_pos = range.to - trailing_spaces
        buffer[semicolon_pos] = SEMICOLON if semicolon_pos < buffer.size

        render_output_marker(node) if output_node?(node) && !tail_expression?(node)
      end

      # @rbs node: ::Herb::AST::Node
      def render_output_marker(node) #: void
        pos = node.tag_opening.range.from
        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = SPACE
        buffer[pos + 2] = EQUALS
      end

      # Render HTML open tag as Ruby code
      # When as_brace is true, uses brace notation: "div { "
      # Otherwise, uses semicolon notation: "div; "
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      # @rbs as_brace: bool
      def render_open_tag_node(node, as_brace:) #: void
        tag_name = node.tag_name.value
        ruby_code = as_brace ? "#{tag_name} { " : "#{tag_name}; "

        start_pos = node.tag_opening.range.from
        buffer[start_pos, ruby_code.bytesize] = ruby_code.bytes
      end

      # Render HTML close tag as Ruby code
      # When as_brace is true, renders "}" only
      # Otherwise, renders "tagN; " with counter to distinguish closing tags
      # @rbs node: ::Herb::AST::HTMLCloseTagNode
      # @rbs as_brace: bool
      def render_close_tag_node(node, as_brace:) #: void
        start_pos = node.tag_opening.range.from

        if as_brace
          buffer[start_pos] = RIGHT_BRACE
        else
          tag_name = node.tag_name.value
          ruby_code = "#{tag_name}#{next_tag_counter}; "
          buffer[start_pos, ruby_code.bytesize] = ruby_code.bytes
        end
      end

      # Render HTML text node by placing "_N;" at first non-whitespace position
      # This indicates content presence to avoid Lint/EmptyBlock and similar cops
      # Uses "_N" with counter to avoid false positives from Style/IdenticalConditionalBranches
      # Requires at least 4 bytes from the first non-whitespace position to end
      # @rbs node: ::Herb::AST::HTMLTextNode
      def render_text_node(node) #: void
        range = NodeRange.compute(node, parse_result)
        text = byteslice(range)
        match = text.match(/\S/)
        return unless match

        pos = range.from + match.begin(0)
        return unless pos + 4 <= range.to

        render_tag_marker(pos)

        # Skip recording tag info for text with multi-byte characters
        # Multi-byte chars are bleached to multiple spaces, changing character count
        # If we restore the original text, character positions would mismatch
        record_tag_info(node) unless text.bytesize != text.length
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
        hash_pos = node.tag_opening.range.to - 1
        buffer[hash_pos] = HASH

        ruby_code = ruby_code_for(node)
        range = node.content.range
        hash_column = node.tag_opening.location.start.column + 2
        formatted_code = format_multiline_comment(ruby_code, hash_column)
        buffer[range.from, formatted_code.bytesize] = formatted_code.bytes
      end

      # Render HTML comment as "_N;" to indicate content presence (like text nodes)
      # Places "_N;" at the start of the comment with counter
      # Uses "_N" with counter to avoid false positives from Style/IdenticalConditionalBranches
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def render_html_comment_node(node) #: void
        range = NodeRange.compute(node)
        text = byteslice(range)

        render_tag_marker(node.comment_start.range.from)

        # Skip recording tag info for comments with multi-byte characters
        # to preserve character count between ruby_code and hybrid_code
        record_tag_info(node) unless text.bytesize != text.length
      end

      # Render tag marker "_x;" at the given position and increment counter
      # Uses alphabetic markers (_a, _b, ... _z) to avoid conflict with Ruby's numbered parameters (_1, _2, etc.)
      # @rbs pos: Integer
      def render_tag_marker(pos) #: void
        buffer[pos] = UNDERSCORE
        buffer[pos + 1] = LOWERCASE_A + next_tag_counter
        buffer[pos + 2] = SEMICOLON
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

      # Build ERB tags from erb_locations for AST restoration
      def build_erb_tags #: Hash[Integer, Tag]
        erb_locations.transform_values do |loc|
          Tag.new(range: loc.range, restore_source: false)
        end
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String
        byteslice(node.content.range)
      end

      # Record tag info for AST restoration
      # @rbs node: html_node
      def record_tag_info(node) #: void
        range = NodeRange.compute(node, parse_result)
        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Check if an HTML node contains ERB
      # @rbs node: html_node
      def contains_erb?(node) #: bool
        parse_result.contains_erb?(NodeRange.compute(node, parse_result))
      end
    end
  end
end
