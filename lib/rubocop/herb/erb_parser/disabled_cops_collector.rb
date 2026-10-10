# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Visitor that collects the lines where cops should be disabled.
    # Some cops report false positives because HTML parts are removed from the Ruby code.
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
        super
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        disable_conditional_cops(node)
        super
      end

      # Else branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBElseNode
      def visit_erb_else_node(node) #: void
        disable_cop("Style/EmptyElse", node) if html_content?(node.statements)
        super
      end

      # When branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBWhenNode
      def visit_erb_when_node(node) #: void
        disable_cop("Lint/EmptyWhen", node) if html_content?(node.statements)
        super
      end

      # Rescue clauses containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBRescueNode
      def visit_erb_rescue_node(node) #: void
        disable_cop("Lint/SuppressedException", node) if html_content?(node.statements)
        super
      end

      # Ensure clauses containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBEnsureNode
      def visit_erb_ensure_node(node) #: void
        disable_cop("Lint/EmptyEnsure", node) if html_content?(node.statements)
        super
      end

      # In branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBInNode
      def visit_erb_in_node(node) #: void
        disable_cop("Lint/EmptyInPattern", node) if html_content?(node.statements)
        super
      end

      # Blocks containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        disable_cop("Lint/EmptyBlock", node) if html_content?(node.body)
        super
      end

      # HTML elements rendered as `tag { ... }` (html_visualization) are not blocks written by users
      # @rbs node: ::Herb::AST::HTMLElementNode
      def visit_html_element_node(node) #: void
        disable_html_block_cops(node) if html_block_positions.include?(node)
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
        disable_line("Layout/SpaceInsideBlockBraces", close_tag_line) if close_tag_line != open_tag_line

        # The braces are restored to the HTML tags, so the cop regards a single-line block as a do...end block
        disable_line("Style/SingleLineDoEndBlock", open_tag_line) if close_tag_line == open_tag_line
        # The content following the open tag is the block body on the same line as `{`
        disable_line("Layout/MultilineBlockLayout", open_tag_line) if first_content_line(node.body) == open_tag_line
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
