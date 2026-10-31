# frozen_string_literal: true

require "forwardable"
require "herb"
require_relative "escaped_erb_visitor"
require_relative "node_range"

module RuboCop
  module Herb
    # Visitor-based renderer that traverses Herb AST and renders Ruby code.
    # Comments are retrieved from ParseResult and rendered at the end
    # with filtering applied.
    class RubyRenderer < ::Herb::Visitor
      extend Forwardable
      include EscapedErbVisitor

      # The position to render the marker of a text node:
      # 3 characters in the line followed by at least 1 character (space or newline) for "_a;",
      # or 2 characters followed by a newline for "_a" (the newline terminates the statement)
      TEXT_MARKER_POSITION = /\S(?:[^\r\n]{2}.|[^\r\n](?=\r?\n))/m #: Regexp

      # Render ERB source to Ruby code
      # @rbs parse_result: ParseResult
      def self.render(parse_result) #: String
        renderer = new(parse_result)
        parse_result.ast.visit(renderer)
        renderer.ruby_code
      end

      attr_reader :ruby_code #: String
      attr_reader :parse_result #: ParseResult
      attr_reader :commented_out_ranges #: Array[CharRange] -- ranges of the code commented out by trailing comments

      # @rbs!
      #   def source: () -> Source
      #   def erb_comment_nodes: () -> Array[::Herb::AST::ERBCommentNode]
      #   def followed_by_content?: (erb_node node) -> bool
      #   def byteslice: (::Herb::Range) -> String

      def_delegators :parse_result, :source, :erb_comment_nodes,
                     :followed_by_content?, :byteslice

      # @rbs parse_result: ParseResult
      def initialize(parse_result) #: void
        @parse_result = parse_result
        @ruby_code = bleach_code(parse_result.code)
        @commented_out_ranges = []

        super()
      end

      # Override to render comments after document traversal completes
      # @rbs node: ::Herb::AST::DocumentNode
      def visit_document_node(node) #: void
        super
        render_comments
        render_commented_out_code
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
      #   def visit_erb_case_match_node: (::Herb::AST::ERBCaseMatchNode node) -> void
      #   def visit_erb_in_node: (::Herb::AST::ERBInNode node) -> void
      #   def visit_erb_yield_node: (::Herb::AST::ERBYieldNode node) -> void
      #   def visit_erb_end_node: (::Herb::AST::ERBEndNode node) -> void

      # Define visit methods for ERB nodes that render code and continue traversal
      %i[block for while until if unless else when in begin rescue ensure case case_match yield end].each do |type|
        define_method(:"visit_erb_#{type}_node") do |node|
          # @type self: RubyRenderer
          # @type var node: erb_node
          render_code_node(node)
          visit_child_nodes(node)
        end
      end

      # Visit ERB content nodes (the actual Ruby code: <% %>, <%= %> or <%== %>)
      # Comments (ERBCommentNode) are not visited here; they are rendered later via render_comments
      # @rbs node: ::Herb::AST::ERBContentNode
      def visit_erb_content_node(node) #: void
        render_code_node(node)
        super
      end

      # Visit HTML element nodes (container for open tag, content, and close tag)
      # If the element contains ERB nodes, its children are processed (the tags are rendered by the visitors below)
      # If the element contains no ERB nodes, renders only the open tag name with full element range
      # HTML elements are not rendered as Ruby blocks because ERB does not create a scope for them
      # (e.g. a local variable assigned in an element is available after the element)
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        return super if contains_erb?(node)

        render_tag_node(node.open_tag)
      end

      # Visit HTML open tag nodes and render them as "tag; "
      # This also renders open tags not wrapped by an element
      # (e.g. an open tag without the close tag, or open tags in the branches of a conditional)
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def visit_html_open_tag_node(node) #: void
        render_tag_node(node)
        super
      end

      # Visit HTML close tag nodes and render them as "tag; "
      # This also renders close tags not wrapped by an element (e.g. a close tag in a conditional)
      # @rbs node: ::Herb::AST::HTMLCloseTagNode
      def visit_html_close_tag_node(node) #: void
        render_tag_node(node)
        super
      end

      # Visit HTML text nodes (plain text content between tags)
      # Renders a marker to indicate content presence
      # @rbs node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(node) #: void
        render_text_node(node)
        super
      end

      # Visit escaped ERB tags (e.g. `<%% x %>`), which are text
      # Renders the tag marker ("_a;") over the tag opening (`<%%`) to indicate content presence (like text nodes)
      # @rbs node: ::Herb::AST::Node
      def visit_escaped_erb_node(node) #: void
        erb = node #: erb_node
        render_tag_marker(byte_to_char_pos(erb.tag_opening.not_nil!.range.from))
        super
      end

      # Visit HTML comment nodes (<!-- ... -->)
      # Comments containing ERB are processed normally (super visits children)
      # Pure HTML comments are rendered as "__;" to indicate content presence (like text nodes)
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def visit_html_comment_node(node) #: void
        if contains_erb?(node)
          super
        else
          render_html_comment_node(node)
        end
      end

      private

      # @rbs node: erb_node
      def output_node?(node) #: bool
        ErbLocation::OUTPUT_TAG_OPENINGS.include?(node.tag_opening&.value)
      end

      # @rbs node: erb_node
      def render_code_node(node) #: void
        return unless node.content

        code = extract_ruby_code(node)
        range = NodeRange.byte_range_to_char_range(node.content.not_nil!.range, source)
        ruby_code[range.from, code.length] = code

        render_statement_end(node, code, range)
        render_output_marker(node) if output_node?(node) && output_expression?(code)
      end

      # Terminate the statement of the code
      # A trailing comment terminates the statement at the end of the line, so no semicolon is rendered
      # (it would break a directive in the comment). The comment comments out the ERB tags and HTML
      # following it on the same line, as ERB does (reported by Herb/CommentedOutCode cop);
      # the HTML is rendered as spaces later (see render_commented_out_code)
      # @rbs node: erb_node
      # @rbs code: String
      # @rbs range: CharRange -- character range of the code
      def render_statement_end(node, code, range) #: void
        unless RubyComment.trailing_range(node, source)
          render_semicolon(node, code, range)
          return
        end

        tag_closing = node.tag_closing
        commented_out_ranges << rest_of_line(tag_closing.range.to) if tag_closing
      end

      # Character range from the byte position to the end of its line
      # The newline is searched by byte position, as String#index with a character position
      # scans the code from its start
      # @rbs byte_pos: Integer
      def rest_of_line(byte_pos) #: CharRange
        code = parse_result.code
        line_end = code.byteindex("\n", byte_pos) || code.bytesize
        CharRange.new(byte_to_char_pos(byte_pos), byte_to_char_pos(line_end))
      end

      # Render a semicolon after the code to terminate the statement
      # A node split from an ERB tag (e.g. `<% else; end %>`) has no tag closing; the following node
      # continues in the same tag, so the code is kept as written
      # The code followed by a newline (e.g. `%>` on its own line) is already terminated by the newline,
      # so the whitespace after the code is kept as written to keep the lines of the source
      # (and the trailing whitespace of the line)
      # @rbs node: erb_node
      # @rbs code: String
      # @rbs range: CharRange
      def render_semicolon(node, code, range) #: void
        return unless node.tag_closing

        trailing_spaces = code[code.rstrip.length..].to_s
        return if trailing_spaces.include?("\n")

        semicolon_pos = range.to - trailing_spaces.length
        ruby_code[semicolon_pos] = ";" if semicolon_pos < ruby_code.size
      end

      # Render `_ =` marker over the output tag opening (`<%=` or `<%==`) to avoid Lint/Void false positives
      # The marker is rendered for every output tag with an expression (see output_expression?), including
      # the last statement of a conditional, because the HTML following the conditional puts it in void context.
      # The marker is placed at the end of the tag opening (`<%==` becomes ` _ =`) so that the space
      # between the tag opening and the code is kept as the space after `=`
      # @rbs node: erb_node
      def render_output_marker(node) #: void
        pos = byte_to_char_pos(node.tag_opening.not_nil!.range.to) - 3
        ruby_code[pos, 3] = "_ ="
      end

      # Whether the code of an output tag has an expression to assign to the output marker
      # Code with only whitespace and comments (e.g. `<%= %>` and `<%= # note %>`) has none, so it is rendered
      # like a code tag (`<% # note %>`). herb-lint reports the comments in output tags (erb-comment-syntax)
      # @rbs code: String
      def output_expression?(code) #: bool
        code.lines.any? { !_1.sub(/#.*/, "").strip.empty? }
      end

      # Render HTML open tag or close tag as Ruby code: "tag; "
      # The tag name and "; " always fit in the tag ("<tag>" or "</tag>")
      # When the tag name is followed by a newline (e.g. `<div\n  class="a">`), the space is dropped ("tag;")
      # so as not to overwrite the newline and shift the following lines
      # @rbs node: ::Herb::AST::Node?
      def render_tag_node(node) #: void
        return unless node.is_a?(::Herb::AST::HTMLOpenTagNode) || node.is_a?(::Herb::AST::HTMLCloseTagNode)

        tag_name = node.tag_name.not_nil!.value
        code = "#{tag_name}; "

        start_pos = byte_to_char_pos(node.tag_opening.not_nil!.range.from)
        code = code.rstrip if newline_at?(start_pos + code.length - 1)
        ruby_code[start_pos, code.length] = code
      end

      # @rbs pos: Integer -- character position in ruby_code
      def newline_at?(pos) #: bool
        ruby_code[pos]&.match?(/[\r\n]/) || false
      end

      # Render HTML text node by placing a marker ("_a;" or "_a") at the first position where it fits in the line
      # (see TEXT_MARKER_POSITION)
      # This indicates content presence to avoid Lint/EmptyBlock and similar cops
      # @rbs node: ::Herb::AST::HTMLTextNode
      def render_text_node(node) #: void
        range = NodeRange.compute_char_range(node, source)
        text = source.slice(range)
        match = text.match(TEXT_MARKER_POSITION)
        return unless match

        pos = range.from + match.begin(0).not_nil!
        if match[0].not_nil!.length > 2
          render_tag_marker(pos)
        else
          ruby_code[pos, 2] = "_a"
        end
      end

      # Render collected comments that can be safely converted to Ruby comments
      # A comment followed by ERB tags or HTML on the same line is not rendered,
      # because Ruby's # comment extends to end of line and would comment them out
      def render_comments #: void
        erb_comment_nodes.each do |node|
          render_erb_comment_node(node) unless followed_by_content?(node)
        end
      end

      # Render the HTML commented out by trailing comments as spaces,
      # so that its markers do not get into the comments (e.g. `div;` breaking a directive in the comment)
      # The ERB tags commented out are kept as rendered
      def render_commented_out_code #: void
        commented_out_ranges.each do |range|
          pos = range.from
          erb_tag_ranges_in(range).each do |tag|
            render_whitespace(pos, tag.from)
            pos = tag.to
          end
          render_whitespace(pos, range.to)
        end
      end

      # Character ranges of the ERB tags starting in the range
      # @rbs range: CharRange
      def erb_tag_ranges_in(range) #: Array[CharRange]
        tags = parse_result.erb_tag_ranges
        index = tags.bsearch_index { _1.from >= range.from } || tags.size
        tags[index..].not_nil!.take_while { _1.from < range.to }
      end

      # Render spaces from the position to the other one (nothing if `to` is not after `from`)
      # @rbs from: Integer
      # @rbs to: Integer
      def render_whitespace(from, to) #: void
        ruby_code[from...to] = " " * (to - from) if from < to
      end

      # @rbs node: ::Herb::AST::ERBCommentNode
      def render_erb_comment_node(node) #: void
        hash_pos = byte_to_char_pos(node.tag_opening.not_nil!.range.to - 1)
        comment = RubyComment.render(node)
        ruby_code[hash_pos, comment.length] = comment
      end

      # Render HTML comment as "_a;" at the start of the comment to indicate content presence (like text nodes)
      # @rbs node: ::Herb::AST::HTMLCommentNode
      def render_html_comment_node(node) #: void
        render_tag_marker(byte_to_char_pos(node.comment_start.not_nil!.range.from))
      end

      # Render tag marker "_a;" at the given position
      # Uses an alphabetic marker to avoid conflict with Ruby's numbered parameters (_1, _2, etc.)
      # @rbs pos: Integer -- character position in ruby_code
      def render_tag_marker(pos) #: void
        ruby_code[pos, 3] = "_a;"
      end

      # @rbs code: String
      def bleach_code(code) #: String
        code.gsub(/[^\n\r]/, " ")
      end

      # Convert byte position to character position
      # @rbs byte_pos: Integer
      def byte_to_char_pos(byte_pos) #: Integer
        source.byte_to_char_pos(byte_pos)
      end

      # @rbs node: erb_node
      def extract_ruby_code(node) #: String
        byteslice(node.content.not_nil!.range)
      end

      # Check if an HTML node contains ERB
      # @rbs node: html_node
      def contains_erb?(node) #: bool
        parse_result.contains_erb?(NodeRange.compute_char_range(node, parse_result.source))
      end
    end
  end
end
