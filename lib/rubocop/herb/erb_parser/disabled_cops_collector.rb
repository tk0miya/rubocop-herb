# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects the lines where cops should be disabled.
    # Some cops report false positives caused by the conversion
    # (e.g. HTML parts are removed, output tags are rendered as `_ = expr`).
    # This collector finds such lines from the ERB structure.
    class DisabledCopsCollector < ::Herb::Visitor
      # Collect the disabled lines for each cop from a parse result
      # @rbs ast: ::Herb::ParseResult
      # @rbs html_block_positions: Set[::Herb::AST::HTMLElementNode] -- HTML elements rendered as `tag { ... }`
      def self.collect(ast, html_block_positions: Set.new) #: Hash[String, Array[Range[Integer]]]
        collector = new(html_block_positions)
        ast.visit(collector)
        collector.disabled_cops
      end

      attr_reader :disabled_cops #: Hash[String, Array[Range[Integer]]]
      attr_reader :html_block_positions #: Set[::Herb::AST::HTMLElementNode]

      # @rbs html_block_positions: Set[::Herb::AST::HTMLElementNode]
      def initialize(html_block_positions) #: void
        @disabled_cops = {}
        @html_block_positions = html_block_positions

        super()
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        disable_conditional_cops(node)
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node # elsif nodes have no end tag
        disable_body_indentation(node.statements)
        super
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        disable_conditional_cops(node)
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node
        disable_body_indentation(node.statements)
        super
      end

      # Output tags in the branches are all rendered as `_ = ...` (to avoid Lint/Void)
      # @rbs node: ::Herb::AST::ERBCaseNode
      def visit_erb_case_node(node) #: void
        disable_cop("Style/ConditionalAssignment", node)
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node
        super
      end

      # Output tags in the branches are all rendered as `_ = ...` (to avoid Lint/Void)
      # @rbs node: ::Herb::AST::ERBCaseMatchNode
      def visit_erb_case_match_node(node) #: void
        disable_cop("Style/ConditionalAssignment", node)
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node
        super
      end

      # The end tag of loops follows the HTML structure
      # @rbs node: ::Herb::AST::ERBWhileNode
      def visit_erb_while_node(node) #: void
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node
        disable_body_indentation(node.statements)
        super
      end

      # The end tag of loops follows the HTML structure
      # @rbs node: ::Herb::AST::ERBUntilNode
      def visit_erb_until_node(node) #: void
        end_node = node.end_node
        disable_end_alignment(end_node) if end_node
        disable_body_indentation(node.statements)
        super
      end

      # The body of loops is indented by the HTML structure
      # @rbs node: ::Herb::AST::ERBForNode
      def visit_erb_for_node(node) #: void
        disable_body_indentation(node.statements)
        super
      end

      # The body of begin is indented by the HTML structure
      # @rbs node: ::Herb::AST::ERBBeginNode
      def visit_erb_begin_node(node) #: void
        disable_body_indentation(node.statements)
        super
      end

      # Else branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        disable_cop("Style/EmptyElse", node) if html_content?(node.statements)
        disable_body_indentation(node.statements)
        super
      end

      # When branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        disable_cop("Lint/EmptyWhen", node) if html_content?(node.statements)
        disable_body_indentation(node.statements)
        super
      end

      # Rescue clauses containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        disable_cop("Lint/SuppressedException", node) if html_content?(node.statements)
        disable_body_indentation(node.statements)
        super
      end

      # Ensure clauses containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        disable_cop("Lint/EmptyEnsure", node) if html_content?(node.statements)
        disable_body_indentation(node.statements)
        super
      end

      # In branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBInNode
      def visit_erb_in_node(node) #: void
        disable_cop("Lint/EmptyInPattern", node) if html_content?(node.statements)
        disable_body_indentation(node.statements)
        super
      end

      # Blocks containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        disable_cop("Lint/EmptyBlock", node) if html_content?(node.body)
        disable_single_line_block(node)
        end_node = node.end_node
        disable_block_alignment(end_node) if end_node
        disable_body_indentation(node.body)
        super
      end

      # HTML elements rendered as `tag { ... }` (html_visualization) are not blocks written by users
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        if html_block_positions.include?(node)
          disable_html_block_cops(node)
          disable_body_indentation(node.body)
        end
        super
      end

      private

      # Disable the cops reporting the braces of an HTML element rendered as `tag { ... }`
      # @rbs node: ::Herb::AST::HTMLElementNode
      def disable_html_block_cops(node) #: void
        open_tag_line = node.open_tag.not_nil!.location.start.line
        close_tag_line = node.close_tag.not_nil!.location.start.line

        # `{` is rendered right after the tag name, and `}` at the start of the close tag
        disable_line("Layout/SpaceBeforeBlockBraces", open_tag_line)
        disable_line("Layout/SpaceInsideBlockBraces", open_tag_line)

        if close_tag_line == open_tag_line
          # The braces are restored to the HTML tags, so the cops regard a single-line block as a do...end block
          disable_line("Style/SingleLineDoEndBlock", open_tag_line)
          disable_line("Style/BlockDelimiters", open_tag_line)
        else
          disable_line("Layout/SpaceInsideBlockBraces", close_tag_line)
          # The alignment of the close tag is a matter of HTML, not Ruby
          disable_line("Layout/BlockAlignment", close_tag_line)
        end
        # The content following the open tag is the block body on the same line as `{`
        disable_line("Layout/MultilineBlockLayout", open_tag_line) if first_content_line(node.body) == open_tag_line
      end

      # Blocks written across multiple ERB tags on a single line become `foo do ...; end` in the Ruby code.
      # Style/BlockDelimiters suggests braces for them, but braces across ERB tags are discouraged
      # (herb-lint's erb-prefer-do-end-blocks). Blocks written within a single ERB tag are still checked.
      # @rbs node: ::Herb::AST::ERBBlockNode
      def disable_single_line_block(node) #: void
        first_line = node.location.start.line
        return unless first_line == node.location.end.line

        disable_line("Style/BlockDelimiters", first_line)
      end

      # The column of the end tag follows the HTML structure (e.g. `<p>x</p><% end %>`),
      # not the opening tag. Conditionals and loops written within a single ERB tag are still checked.
      # @rbs end_node: ::Herb::AST::ERBEndNode
      def disable_end_alignment(end_node) #: void
        disable_cop("Layout/EndAlignment", end_node)
      end

      # The column of the end tag follows the HTML structure, and the block start is shifted by the output marker
      # (`<%= form_with do |f| %>` becomes `_ = form_with do |f|;`). Blocks written within a single ERB tag
      # are still checked.
      # @rbs end_node: ::Herb::AST::ERBEndNode
      def disable_block_alignment(end_node) #: void
        disable_cop("Layout/BlockAlignment", end_node)
      end

      # The bodies of conditionals, loops and blocks written across ERB tags (and HTML blocks) are indented
      # by the HTML structure. Layout/IndentationWidth reports the first statement of a body, which is
      # the first HTML content (html_visualization) or the first ERB tag in it, so the cop is disabled
      # from the first content to the first ERB tag. ERB tags without Ruby code (e.g. `<%# note %>` and
      # `<% # note %>`) are skipped as they are not statements. Bodies written within a single ERB tag
      # are still checked.
      # @rbs nodes: Array[::Herb::AST::Node]
      def disable_body_indentation(nodes) #: void
        first_line = first_content_line(nodes.reject { codeless_erb?(_1) })
        return unless first_line

        last_line = first_erb_line(nodes) || first_line
        (disabled_cops["Layout/IndentationWidth"] ||= []) << (first_line..last_line)
      end

      # The line of the Ruby code in the first ERB tag (except the ones without code) in the nodes,
      # including the ones in HTML elements
      # @rbs nodes: Array[::Herb::AST::Node]
      def first_erb_line(nodes) #: Integer?
        nodes.each do |node|
          next if codeless_erb?(node)
          return ruby_code_line(node) if node.type.start_with?("AST_ERB_")

          line = first_erb_line(node.compact_child_nodes)
          return line if line
        end
        nil
      end

      # Whether the node is an ERB comment or an ERB tag containing only whitespace and Ruby comments
      # @rbs node: ::Herb::AST::Node
      def codeless_erb?(node) #: bool
        return true if node.is_a?(::Herb::AST::ERBCommentNode)
        return false unless node.is_a?(::Herb::AST::ERBContentNode)

        code_line_offset(node.content&.value.to_s).nil?
      end

      # The line of the first Ruby code in the ERB tag
      # (e.g. the line next to `<%` for a tag whose code starts at the next line)
      # @rbs node: ::Herb::AST::Node
      def ruby_code_line(node) #: Integer
        erb = node #: erb_node
        content = erb.content
        offset = code_line_offset(content&.value.to_s)
        return erb.location.start.line unless content && offset

        content.location.start.line + offset
      end

      # The index of the first line containing Ruby code (except whitespace and comments) in the code
      # @rbs code: String
      def code_line_offset(code) #: Integer?
        code.lines.index { !_1.sub(/#.*/, "").strip.empty? }
      end

      # The line of the first non-whitespace content in the nodes
      # @rbs nodes: Array[::Herb::AST::Node]
      def first_content_line(nodes) #: Integer?
        nodes.each do |node|
          return node.location.start.line unless node.is_a?(::Herb::AST::HTMLTextNode)

          leading_text = node.content.to_s[/\A\s*(?=\S)/]
          return node.location.start.line + leading_text.count("\n") if leading_text
        end
        nil
      end

      # @rbs cop_name: String
      # @rbs line: Integer
      def disable_line(cop_name, line) #: void
        (disabled_cops[cop_name] ||= []) << (line..line)
      end

      # Disable the cops reporting conditionals written across multiple ERB tags
      # Conditionals written within a single ERB tag are not ERBIfNode, so they are still checked.
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBUnlessNode
      def disable_conditional_cops(node) #: void
        return unless node.end_node # elsif nodes are checked as a part of the outer if node

        # A semicolon is rendered at the closing of the if tag (`if a;`)
        disable_cop("Style/IfWithSemicolon", node)
        # Converting them to modifier form breaks the template (e.g. it drops HTML)
        disable_cop("Style/IfUnlessModifier", node)
        # Output tags in the branches are all rendered as `_ = ...` (to avoid Lint/Void)
        disable_cop("Style/ConditionalAssignment", node)
        # Output tags in the branches are rendered as `_ = a`, so the condition looks redundant
        # (`if a; _ = a; else; _ = b; end`)
        disable_cop("Style/RedundantCondition", node)
        # Converting them to `next` breaks the template (e.g. it leaves the closing of the end tag)
        disable_cop("Style/Next", node)
        disable_one_line_conditional(node)
      end

      # Conditionals written across multiple ERB tags on a single line become
      # `if a; ...; else; ...; end` in the Ruby code. Style/OneLineConditional
      # reports them, but its autocorrect breaks the template (e.g. it drops HTML).
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBUnlessNode
      def disable_one_line_conditional(node) #: void
        first_line = node.location.start.line
        return unless first_line == node.location.end.line

        disable_line("Style/OneLineConditional", first_line)
      end

      # Disable the cop at the lines of the ERB tag
      # A node split from an ERB tag (e.g. `<% case x when 1 %>`) lacks its tag opening or closing,
      # so its content is used instead
      # @rbs cop_name: String
      # @rbs node: erb_node
      def disable_cop(cop_name, node) #: void
        first_line = (node.tag_opening || node.content).not_nil!.location.start.line
        last_line = (node.tag_closing || node.content).not_nil!.location.end.line
        (disabled_cops[cop_name] ||= []) << (first_line..last_line)
      end

      # Check if the nodes contain non-ERB content (except whitespace)
      # @rbs nodes: Array[::Herb::AST::Node]
      def html_content?(nodes) #: bool
        nodes.any? do |node|
          if node.is_a?(::Herb::AST::HTMLTextNode)
            node.content.to_s.match?(/\S/)
          else
            !node.type.start_with?("AST_ERB_")
          end
        end
      end
    end
  end
end
