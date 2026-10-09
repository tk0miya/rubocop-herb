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
      def self.collect(ast) #: Hash[String, Array[Range[Integer]]]
        collector = new
        ast.visit(collector)
        collector.disabled_cops
      end

      attr_reader :disabled_cops #: Hash[String, Array[Range[Integer]]]

      def initialize #: void
        @disabled_cops = {}

        super
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBIfNode
      def visit_erb_if_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        disable_one_line_conditional(node)
        super
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        disable_one_line_conditional(node)
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

      # Blocks containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBBlockNode
      def visit_erb_block_node(node) #: void
        disable_cop("Lint/EmptyBlock", node) if html_content?(node.body)
        super
      end

      private

      # Conditionals written across multiple ERB tags on a single line become
      # `if a; ...; else; ...; end` in the Ruby code. Style/OneLineConditional
      # reports them, but its autocorrect breaks the template (e.g. it drops HTML).
      # Conditionals written within a single ERB tag are not ERBIfNode, so they are still checked.
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBUnlessNode
      def disable_one_line_conditional(node) #: void
        return unless node.end_node # elsif nodes are checked as a part of the outer if node

        first_line = node.location.start.line
        return unless first_line == node.location.end.line

        (disabled_cops["Style/OneLineConditional"] ||= []) << (first_line..first_line)
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
