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
        super
      end

      # Conditional branches containing only HTML become empty in the Ruby code
      # @rbs node: ::Herb::AST::ERBUnlessNode
      def visit_erb_unless_node(node) #: void
        disable_cop("Lint/EmptyConditionalBody", node) if html_content?(node.statements)
        super
      end

      private

      # Disable the cop at the lines of the ERB tag
      # @rbs cop_name: String
      # @rbs node: ::Herb::AST::ERBIfNode | ::Herb::AST::ERBUnlessNode
      def disable_cop(cop_name, node) #: void
        first_line = node.tag_opening.not_nil!.location.start.line
        last_line = node.tag_closing.not_nil!.location.end.line
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
