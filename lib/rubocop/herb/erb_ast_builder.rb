# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Builds an ErbAst from a Herb AST by extracting only ERB nodes.
    # HTML nodes are filtered out, preserving the hierarchical structure of ERB nodes.
    class ErbAstBuilder # rubocop:disable Metrics/ClassLength
      # Builds an array of ErbAst::Node from a Herb parse result.
      # @rbs parse_result: ::Herb::ParseResult
      def build(parse_result) #: Array[ErbAst::Node]
        extract_erb_nodes(parse_result.value.children)
      end

      private

      # Extracts ERB nodes from a collection of Herb AST nodes.
      # HTML nodes are traversed but not included in the result.
      # @rbs nodes: Array[::Herb::AST::Node]
      def extract_erb_nodes(nodes) #: Array[ErbAst::Node] # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        result = [] #: Array[ErbAst::Node]

        nodes.each do |node|
          case node
          when ::Herb::AST::ERBIfNode
            result << build_if_node(node)
          when ::Herb::AST::ERBUnlessNode
            result << build_unless_node(node)
          when ::Herb::AST::ERBCaseNode
            result << build_case_node(node)
          when ::Herb::AST::ERBBeginNode
            result << build_begin_node(node)
          when ::Herb::AST::ERBBlockNode
            result << build_block_node(node)
          when ::Herb::AST::ERBForNode, ::Herb::AST::ERBWhileNode, ::Herb::AST::ERBUntilNode
            result << build_loop_node(node)
          when ::Herb::AST::ERBContentNode, ::Herb::AST::ERBYieldNode
            result << ErbAst::Node.new(node)
          when ::Herb::AST::HTMLElementNode
            # Traverse HTML element's body to find nested ERB nodes
            result.concat(extract_erb_nodes(node.body)) if node.respond_to?(:body) && node.body
          when ::Herb::AST::HTMLTextNode
            # Skip HTML text nodes
          else
            # For other nodes, try to extract from child_nodes
            result.concat(extract_erb_nodes(node.child_nodes)) if node.respond_to?(:child_nodes)
          end
        end

        result
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def build_if_node(node) #: ErbAst::Node
        children = extract_erb_nodes(node.statements)
        children.concat(build_subsequent_nodes(node.subsequent)) if node.subsequent
        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end

      # Builds nodes from subsequent (elsif/else chain).
      # @rbs subsequent: ::Herb::AST::Node?
      def build_subsequent_nodes(subsequent) #: Array[ErbAst::Node]
        return [] unless subsequent

        result = [] #: Array[ErbAst::Node]

        case subsequent
        when ::Herb::AST::ERBIfNode
          # elsif node
          children = extract_erb_nodes(subsequent.statements)
          children.concat(build_subsequent_nodes(subsequent.subsequent)) if subsequent.subsequent
          result << ErbAst::Node.new(subsequent, children)
        when ::Herb::AST::ERBElseNode
          children = extract_erb_nodes(subsequent.statements)
          result << ErbAst::Node.new(subsequent, children)
        end

        result
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def build_unless_node(node) #: ErbAst::Node
        children = extract_erb_nodes(node.statements)
        if node.else_clause
          else_children = extract_erb_nodes(node.else_clause.statements)
          children << ErbAst::Node.new(node.else_clause, else_children)
        end
        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def build_case_node(node) #: ErbAst::Node
        children = [] #: Array[ErbAst::Node]

        node.conditions.each do |when_node|
          when_children = extract_erb_nodes(when_node.statements)
          children << ErbAst::Node.new(when_node, when_children)
        end

        if node.else_clause
          else_children = extract_erb_nodes(node.else_clause.statements)
          children << ErbAst::Node.new(node.else_clause, else_children)
        end

        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def build_begin_node(node) #: ErbAst::Node # rubocop:disable Metrics/AbcSize
        children = extract_erb_nodes(node.statements)
        children.concat(build_rescue_nodes(node.rescue_clause)) if node.rescue_clause

        if node.else_clause
          else_children = extract_erb_nodes(node.else_clause.statements)
          children << ErbAst::Node.new(node.else_clause, else_children)
        end

        if node.ensure_clause
          ensure_children = extract_erb_nodes(node.ensure_clause.statements)
          children << ErbAst::Node.new(node.ensure_clause, ensure_children)
        end

        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end

      # Builds nodes from rescue chain.
      # @rbs rescue_node: ::Herb::AST::ERBRescueNode?
      def build_rescue_nodes(rescue_node) #: Array[ErbAst::Node]
        return [] unless rescue_node

        result = [] #: Array[ErbAst::Node]
        current = rescue_node

        while current
          children = extract_erb_nodes(current.statements)
          result << ErbAst::Node.new(current, children)
          current = current.subsequent
        end

        result
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def build_block_node(node) #: ErbAst::Node
        children = extract_erb_nodes(node.body)
        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end

      # Builds a loop node (for/while/until).
      # @rbs node: ::Herb::AST::Node
      def build_loop_node(node) #: ErbAst::Node
        children = extract_erb_nodes(node.statements)
        children << ErbAst::Node.new(node.end_node) if node.end_node

        ErbAst::Node.new(node, children)
      end
    end
  end
end
