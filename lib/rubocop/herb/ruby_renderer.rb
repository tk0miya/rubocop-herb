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
    # The texts too short for the marker are not rendered in the Ruby code, as it keeps the positions of the source.
    # They are collected in short_text_ranges instead (see ExpandedCode).
    class RubyRenderer < ::Herb::Visitor
      extend Forwardable
      include EscapedErbVisitor

      # The position to render the marker of a text node:
      # 3 characters in the line for "_a;" (the code following the text may follow the semicolon: `_a;_ = x;`),
      # or 2 characters followed by a newline for "_a" (the newline terminates the statement)
      TEXT_MARKER_POSITION = /\S(?:[^\r\n]{2}|[^\r\n](?=\r?\n))/ #: Regexp

      # The position to render the marker of a text node too short for TEXT_MARKER_POSITION
      # (e.g. `[` in `  [<%= x %>]`): the marker starts at the whitespace before the text in the line
      # (part of the text node), so that the text is not rendered as whitespace
      INDENTED_TEXT_MARKER_POSITION = /[^\S\r\n](?:[^\S\r\n]\S|\S[^\r\n]|\S(?=\r?\n))/ #: Regexp

      # The short text to collect in a text too short to place the marker: 1-2 characters
      SHORT_TEXT = /\S\S?/ #: Regexp

      # Render ERB source to Ruby code
      # @rbs parse_result: ParseResult
      def self.render(parse_result) #: RubyRenderer
        renderer = new(parse_result)
        parse_result.ast.visit(renderer)
        renderer
      end

      # Find the position to render the marker of a text node (nil if the text is too short to place it)
      # The marker is placed at the text (see TEXT_MARKER_POSITION) and, only when the text is too short in every line,
      # over the whitespace before the text (see INDENTED_TEXT_MARKER_POSITION), so that the offenses on the marker
      # (e.g. Lint/UnreachableCode) point at the text as much as possible
      # @rbs text: String
      def self.text_marker_position(text) #: MatchData?
        text.match(TEXT_MARKER_POSITION) || text.match(INDENTED_TEXT_MARKER_POSITION)
      end

      # The literals of the name and the value of an attribute (except the ones in ERB nodes) to place the marker of
      # the attribute at. Literals with whitespace only have no text to place it at
      # @rbs node: ::Herb::AST::HTMLAttributeNode
      def self.attribute_literals(node) #: Array[::Herb::AST::LiteralNode]
        children = [*node.name&.children, *node.value&.children] #: Array[::Herb::AST::Node]
        literals = children.grep(::Herb::AST::LiteralNode) #: Array[::Herb::AST::LiteralNode]
        literals.select { _1.content.to_s.match?(/\S/) }
      end

      attr_reader :ruby_code #: String
      attr_reader :short_text_ranges #: Array[CharRange] -- the texts too short to be rendered in the Ruby code
      attr_reader :parse_result #: ParseResult

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
        @short_text_ranges = []
        @in_open_tag = false

        super()
      end

      # Override to render comments after document traversal completes
      # @rbs node: ::Herb::AST::DocumentNode
      def visit_document_node(node) #: void
        super
        render_comments
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
          # The bodies of ERB nodes are branches of their own, even in open tags (see visit_html_open_tag_node)
          within_open_tag(false) { visit_child_nodes(node) }
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

        render_marker(node)
      end

      # Visit HTML open tag nodes and render them as "tag; "
      # This also renders open tags not wrapped by an element
      # (e.g. an open tag without the close tag, or open tags in the branches of a conditional)
      # The attributes in the open tag (e.g. `class="a"`) are a part of the tag, so they are not rendered,
      # except the ones in ERB nodes (see visit_html_attribute_node)
      # @rbs node: ::Herb::AST::HTMLOpenTagNode
      def visit_html_open_tag_node(node) #: void
        render_marker(node)
        within_open_tag(true) { super }
      end

      # Visit HTML attribute nodes
      # An attribute in an ERB node (e.g. `<input <% if a %>disabled<% end %>>`) is a branch of its own,
      # so it is rendered as a marker at its first literal in which the marker fits (or at its first literal)
      # @rbs node: ::Herb::AST::HTMLAttributeNode
      def visit_html_attribute_node(node) #: void
        render_attribute_marker(node) unless in_open_tag
        within_open_tag(true) { super }
      end

      # Visit HTML close tag nodes and render them as "tag; "
      # This also renders close tags not wrapped by an element (e.g. a close tag in a conditional)
      # @rbs node: ::Herb::AST::HTMLCloseTagNode
      def visit_html_close_tag_node(node) #: void
        render_marker(node)
        super
      end

      # Visit HTML text nodes (plain text content between tags)
      # Renders a marker to indicate content presence
      # @rbs node: ::Herb::AST::HTMLTextNode
      def visit_html_text_node(node) #: void
        render_marker(node)
        super
      end

      # Visit literal nodes (e.g. the contents of script elements and comments, and the text in the ERB nodes of
      # attribute values)
      # Renders a marker to indicate content presence, as text nodes do. Otherwise the bodies containing only
      # literals (e.g. `class="<% if a %>active<% end %>"`) become empty in the Ruby code, and the cops skipping
      # empty bodies (e.g. Style/NegatedIfElseCondition) miss offenses.
      # The literals of the attributes in open tags are a part of the tags (see visit_html_open_tag_node)
      # @rbs node: ::Herb::AST::LiteralNode
      def visit_literal_node(node) #: void
        render_marker(node) unless in_open_tag
        super
      end

      # Visit escaped ERB tags (e.g. `<%% x %>`), which are text
      # Renders the tag marker ("_a;") over the tag opening (`<%%`) to indicate content presence (like text nodes)
      # @rbs node: ::Herb::AST::Node
      def visit_escaped_erb_node(node) #: void
        render_marker(node)
        super
      end

      # @rbs!
      #   def visit_html_comment_node: (::Herb::AST::HTMLCommentNode node) -> void
      #   def visit_html_doctype_node: (::Herb::AST::HTMLDoctypeNode node) -> void
      #   def visit_cdata_node: (::Herb::AST::CDATANode node) -> void
      #   def visit_xml_declaration_node: (::Herb::AST::XMLDeclarationNode node) -> void

      # Define visit methods for comments (<!-- ... -->), doctypes (<!DOCTYPE ...>), CDATA (<![CDATA[ ... ]]>)
      # and XML declarations (<?xml ... ?>) (see render_opening_node)
      %i[html_comment html_doctype cdata xml_declaration].each do |type|
        define_method(:"visit_#{type}_node") do |node|
          # @type self: RubyRenderer
          # @type var node: html_opening_node
          render_opening_node(node)
        end
      end

      private

      attr_reader :in_open_tag #: bool -- whether the visitor is in the attributes of an open tag outside ERB nodes

      # Run the block with in_open_tag set, restoring it afterwards
      # @rbs value: bool
      # @rbs &block: () -> void
      def within_open_tag(value, &block) #: void
        saved = in_open_tag
        @in_open_tag = value
        block.call
      ensure
        @in_open_tag = saved || false
      end

      # Render the marker of an attribute at its first literal in which the marker fits
      # (e.g. `disabled` of `<% if a %>disabled<% end %>`), or at its first literal as a short text if it fits in none
      # (e.g. `id` of `<% if a %>id="x"<% end %>`)
      # An attribute without literals (e.g. `<%= k %>="<%= v %>"`) has no marker
      # @rbs node: ::Herb::AST::HTMLAttributeNode
      def render_attribute_marker(node) #: void
        literals = RubyRenderer.attribute_literals(node)
        literal = literals.find { RubyRenderer.text_marker_position(_1.content.to_s) } || literals.first
        render_text_node(literal) if literal
      end

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

        render_semicolon(node, code, range)
        render_output_marker(node) if output_node?(node) && output_expression?(code)
      end

      # Render a semicolon after the code to terminate the statement
      # A node split from an ERB tag (e.g. `<% else; end %>`) has no tag closing; the following node
      # continues in the same tag, so the code is kept as written
      # The code followed by a newline (e.g. `%>` on its own line) is already terminated by the newline,
      # so the whitespace after the code is kept as written to keep the lines of the source
      # (and the trailing whitespace of the line)
      # An empty tag (e.g. `<% %>`) has no statement to terminate, so no semicolon is rendered
      # (a semicolon after the whitespace rendered from the delimiters would trigger Layout/SpaceBeforeSemicolon)
      # @rbs node: erb_node
      # @rbs code: String
      # @rbs range: CharRange
      def render_semicolon(node, code, range) #: void
        return unless node.tag_closing
        return if code.strip.empty?

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
      # Code with only whitespace and comments (e.g. `<%= %>` and `<%= # note` followed by a newline and `%>`)
      # has none, so it is rendered like a code tag. herb-lint reports the comments in output tags (erb-comment-syntax)
      # @rbs code: String
      def output_expression?(code) #: bool
        code.lines.any? { !_1.sub(/#.*/, "").strip.empty? }
      end

      # Render a comment, doctype, CDATA or XML declaration as a marker at its opening (e.g. `<!--`),
      # and process its children (the literals and the ERB nodes) if it contains ERB nodes,
      # as HTML elements are (see visit_html_element_node)
      # @rbs node: html_opening_node
      def render_opening_node(node) #: void
        render_marker(node)
        visit_child_nodes(node) if contains_erb?(node)
      end

      # Render the marker of the HTML node (e.g. "tag; " for tags and "_a;" for text)
      # Text and literals are collected as short texts when the marker does not fit in them (see render_text_node)
      # @rbs node: ::Herb::AST::Node
      def render_marker(node) #: void
        case node
        when ::Herb::AST::HTMLElementNode then render_tag_node(node.open_tag)
        when ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode then render_tag_node(node)
        when ::Herb::AST::HTMLTextNode, ::Herb::AST::LiteralNode then render_text_node(node)
        when ::Herb::AST::HTMLCommentNode then render_tag_marker(node.comment_start.not_nil!)
        when ::Herb::AST::HTMLDoctypeNode, ::Herb::AST::CDATANode, ::Herb::AST::XMLDeclarationNode
          render_tag_marker(node.tag_opening.not_nil!)
        else # escaped ERB tags
          erb = node #: erb_node
          render_tag_marker(erb.tag_opening.not_nil!)
        end
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

      # Render HTML text node (or literal node) as a marker (see render_text_marker)
      # The text too short to place the marker is collected as a short text: its first 1-2 characters
      # (e.g. `a` in `<% if x %>a<% end %>`). One short text is enough to indicate content presence,
      # as one marker is rendered for a text
      # @rbs node: ::Herb::AST::HTMLTextNode | ::Herb::AST::LiteralNode
      def render_text_node(node) #: void
        range = NodeRange.compute_char_range(node, source)
        text = source.slice(range)
        return render_text_marker(range) if RubyRenderer.text_marker_position(text)

        match = text.match(SHORT_TEXT)
        return unless match

        from = range.from + match.begin(0).not_nil!
        short_text_ranges << CharRange.new(from:, to: from + match[0].not_nil!.length)
      end

      # Render HTML text by placing a marker ("_a;" or "_a") at the first position where it fits in the line,
      # or over the whitespace before it (see RubyRenderer.text_marker_position)
      # @rbs range: CharRange -- range of the text
      def render_text_marker(range) #: void
        match = RubyRenderer.text_marker_position(source.slice(range))
        return unless match

        pos = range.from + match.begin(0).not_nil!
        marker = match[0].not_nil!.length > 2 ? "_a;" : "_a"
        ruby_code[pos, marker.length] = marker
      end

      # Render collected comments that can be safely converted to Ruby comments
      # A comment followed by ERB tags or HTML on the same line is not rendered,
      # because Ruby's # comment extends to end of line and would comment them out
      def render_comments #: void
        erb_comment_nodes.each do |node|
          render_erb_comment_node(node) unless followed_by_content?(node)
        end
      end

      # @rbs node: ::Herb::AST::ERBCommentNode
      def render_erb_comment_node(node) #: void
        render_marker_before_comment(byte_to_char_pos(node.tag_opening.not_nil!.range.from))
        hash_pos = byte_to_char_pos(node.tag_opening.not_nil!.range.to - 1)
        comment = RubyComment.render(node)
        ruby_code[hash_pos, comment.length] = comment
      end

      # Render a marker in the HTML preceding an ERB comment in its line when the line has no code,
      # because the marker of the HTML may be rendered in an earlier line (e.g. multi-line text).
      # Otherwise RuboCop regards the comment as a comment on its own line, which changes the meaning of
      # the directives in it (e.g. a directive disabling a cop after `de` of `<div>abc\n  de` disables the cop
      # until the end of the file instead of the line, as the marker of the text is rendered at `abc`)
      # Only the HTML after the last ERB tag in the line is used, as the ERB tags without code
      # (e.g. `<% %>` and `%>` of a multi-line tag) are not HTML
      # @rbs tag_start: Integer -- character position of the tag opening of the comment
      def render_marker_before_comment(tag_start) #: void
        line_start = tag_start.positive? ? (ruby_code.rindex("\n", tag_start - 1) || -1) + 1 : 0
        return if ruby_code[line_start...tag_start].to_s.match?(/\S/)

        html_start = [line_start, preceding_erb_tag_end(tag_start)].max.not_nil!
        render_text_marker(CharRange.new(from: html_start, to: tag_start))
      end

      # The end of the last ERB tag before the position (0 if none)
      # @rbs pos: Integer -- character position
      def preceding_erb_tag_end(pos) #: Integer
        ranges = parse_result.erb_tag_ranges
        index = ranges.bsearch_index { _1.to > pos } || ranges.size
        index.positive? ? ranges[index - 1].not_nil!.to : 0
      end

      # Render tag marker "_a;" at the opening of a node (e.g. `<!--` of comments and `<%%` of escaped ERB tags),
      # which has 3 characters or more
      # Uses an alphabetic marker to avoid conflict with Ruby's numbered parameters (_1, _2, etc.)
      # @rbs opening: ::Herb::Token
      def render_tag_marker(opening) #: void
        ruby_code[byte_to_char_pos(opening.range.from), 3] = "_a;"
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
