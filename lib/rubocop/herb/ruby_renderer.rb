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

      # @rbs!
      #   type html_node = ::Herb::AST::HTMLElementNode
      #                  | ::Herb::AST::HTMLTextNode
      #                  | ::Herb::AST::HTMLOpenTagNode
      #                  | ::Herb::AST::HTMLCloseTagNode
      #                  | ::Herb::AST::HTMLCommentNode

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
        renderer.result
      end

      attr_reader :buffer #: Array[Integer]
      attr_reader :source #: Source
      attr_reader :result #: Result
      attr_reader :block_stack #: Array[BlockContext]
      attr_reader :comment_nodes #: Array[::Herb::AST::Node]
      attr_reader :tag_counter #: Integer
      attr_reader :html_visualization #: bool
      attr_reader :tags #: Hash[Integer, Tag]

      # @rbs source: Source
      # @rbs html_visualization: bool
      def initialize(source, html_visualization: false) #: void
        @source = source
        @buffer = bleach_code(source.code)
        @block_stack = []
        @comment_nodes = []
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
        code = buffer.pack("C*").force_encoding(source.encoding)
        @result = Result.new(source:, code:, tags: all_tags)
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
      def visit_html_element_node(node) #: void
        return super unless html_visualization

        if contains_erb?(node)
          # Only use brace notation if element has a close tag (not for void elements like <meta>, <br>)
          as_brace = node.close_tag && use_brace_notation?(node.open_tag)
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

      # Get the byte range of an HTML node
      # @rbs node: html_node
      def compute_node_range(node) #: ::Herb::Range # rubocop:disable Metrics/AbcSize
        case node
        when ::Herb::AST::HTMLElementNode
          from = node.open_tag.tag_opening.range.from
          to = node.close_tag ? node.close_tag.tag_closing.range.to : node.open_tag.tag_closing.range.to
          ::Herb::Range.new(from, to)
        when ::Herb::AST::HTMLTextNode
          source.location_to_range(node.location)
        when ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode
          ::Herb::Range.new(node.tag_opening.range.from, node.tag_closing.range.to)
        when ::Herb::AST::HTMLCommentNode
          ::Herb::Range.new(node.comment_start.range.from, node.comment_end.range.to)
        end
      end

      # Check if brace notation should be used for the given open tag
      # Brace notation requires at least 3 bytes beyond tag name for " { "
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def use_brace_notation?(node) #: bool
        tag_name = node.tag_name.value
        tag_length = node.tag_closing.range.to - node.tag_opening.range.from
        min_brace_length = tag_name.bytesize + 3 # "tag { " needs tag + " { "
        tag_length >= min_brace_length
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
        range = compute_node_range(node)
        text = source.byteslice(range)
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
        comment_nodes.each do |node|
          render_erb_comment_node(node) if renderable_comment?(node)
        end
      end

      # Check if this comment can be rendered as a Ruby comment without breaking code
      # Comments are not renderable when there's code to the right on the same line,
      # because Ruby's # comment extends to end of line and would comment out the code
      # @rbs node: ::Herb::AST::ERBContentNode
      def renderable_comment?(node) #: bool
        line = node.location.end.line
        return true unless source.erb_max_columns.key?(line)

        node.location.start.column >= source.erb_max_columns[line]
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
        range = compute_node_range(node)
        text = source.byteslice(range)

        render_tag_marker(node.comment_start.range.from)

        # Skip recording tag info for comments with multi-byte characters
        # to preserve character count between ruby_code and hybrid_code
        record_html_comment_tag(node) unless text.bytesize != text.length
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

      # Record tag info for HTML comment AST restoration
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def record_html_comment_tag(node) #: void
        range = compute_node_range(node)
        tags[range.from] = Tag.new(range:, restore_source: true)
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

      # Build ERB tags from source erb_locations for AST restoration
      def build_erb_tags #: Hash[Integer, Tag]
        source.erb_locations.transform_values do |loc|
          Tag.new(range: loc.range, restore_source: false)
        end
      end

      # @rbs node: ::Herb::AST::Node
      def ruby_code_for(node) #: String
        source.byteslice(node.content.range)
      end

      # Record tag info for AST restoration
      # @rbs node: html_node
      def record_tag_info(node) #: void
        range = compute_node_range(node)
        tags[range.from] = Tag.new(range:, restore_source: true)
      end

      # Check if an HTML node contains ERB
      # @rbs node: html_node
      def contains_erb?(node) #: bool
        source.contains_erb?(compute_node_range(node))
      end
    end
  end
end
