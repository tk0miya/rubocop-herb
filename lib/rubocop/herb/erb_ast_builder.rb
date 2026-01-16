# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Builds a filtered ERB AST from a Herb AST by extracting only ERB nodes.
    # HTML nodes are filtered out, preserving the hierarchical structure.
    # Returns Herb::AST node instances with filtered children/statements.
    class ErbAstBuilder # rubocop:disable Metrics/ClassLength
      # Builds an array of Herb AST nodes from a parse result with HTML filtered out.
      # @rbs parse_result: ::Herb::ParseResult
      def build(parse_result) #: Array[::Herb::AST::Node]
        extract_erb_nodes(parse_result.value.children)
      end

      private

      # Extracts ERB nodes from a collection of Herb AST nodes.
      # HTML nodes are traversed but not included in the result.
      # @rbs nodes: Array[::Herb::AST::Node]
      def extract_erb_nodes(nodes) #: Array[::Herb::AST::Node] # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        result = [] #: Array[::Herb::AST::Node]

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
          when ::Herb::AST::ERBContentNode, ::Herb::AST::ERBYieldNode, ::Herb::AST::ERBEndNode
            result << node
          when ::Herb::AST::HTMLElementNode
            result.concat(extract_erb_nodes(node.body)) if node.respond_to?(:body) && node.body
          when ::Herb::AST::HTMLTextNode
            # Skip HTML text nodes
          else
            result.concat(extract_erb_nodes(node.child_nodes)) if node.respond_to?(:child_nodes)
          end
        end

        result
      end

      # @rbs node: ::Herb::AST::ERBIfNode
      def build_if_node(node) #: ::Herb::AST::ERBIfNode
        ::Herb::AST::ERBIfNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          extract_erb_nodes(node.statements),
          build_subsequent(node.subsequent),
          node.end_node
        )
      end

      # @rbs subsequent: ::Herb::AST::Node?
      def build_subsequent(subsequent) #: ::Herb::AST::Node? # rubocop:disable Metrics/AbcSize
        return nil unless subsequent

        case subsequent
        when ::Herb::AST::ERBIfNode
          # elsif node
          ::Herb::AST::ERBIfNode.new(
            subsequent.type,
            subsequent.location,
            subsequent.errors,
            subsequent.tag_opening,
            subsequent.content,
            subsequent.tag_closing,
            extract_erb_nodes(subsequent.statements),
            build_subsequent(subsequent.subsequent),
            subsequent.end_node
          )
        when ::Herb::AST::ERBElseNode
          ::Herb::AST::ERBElseNode.new(
            subsequent.type,
            subsequent.location,
            subsequent.errors,
            subsequent.tag_opening,
            subsequent.content,
            subsequent.tag_closing,
            extract_erb_nodes(subsequent.statements)
          )
        end
      end

      # @rbs node: ::Herb::AST::ERBUnlessNode
      def build_unless_node(node) #: ::Herb::AST::ERBUnlessNode # rubocop:disable Metrics/AbcSize
        else_clause = if node.else_clause
                        ::Herb::AST::ERBElseNode.new(
                          node.else_clause.type,
                          node.else_clause.location,
                          node.else_clause.errors,
                          node.else_clause.tag_opening,
                          node.else_clause.content,
                          node.else_clause.tag_closing,
                          extract_erb_nodes(node.else_clause.statements)
                        )
                      end

        ::Herb::AST::ERBUnlessNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          extract_erb_nodes(node.statements),
          else_clause,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBCaseNode
      def build_case_node(node) #: ::Herb::AST::ERBCaseNode # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        conditions = node.conditions.map do |when_node|
          ::Herb::AST::ERBWhenNode.new(
            when_node.type,
            when_node.location,
            when_node.errors,
            when_node.tag_opening,
            when_node.content,
            when_node.tag_closing,
            extract_erb_nodes(when_node.statements)
          )
        end

        else_clause = if node.else_clause
                        ::Herb::AST::ERBElseNode.new(
                          node.else_clause.type,
                          node.else_clause.location,
                          node.else_clause.errors,
                          node.else_clause.tag_opening,
                          node.else_clause.content,
                          node.else_clause.tag_closing,
                          extract_erb_nodes(node.else_clause.statements)
                        )
                      end

        ::Herb::AST::ERBCaseNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          node.children,
          conditions,
          else_clause,
          node.end_node
        )
      end

      # @rbs node: ::Herb::AST::ERBBeginNode
      def build_begin_node(node) #: ::Herb::AST::ERBBeginNode # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        rescue_clause = build_rescue_chain(node.rescue_clause)

        else_clause = if node.else_clause
                        ::Herb::AST::ERBElseNode.new(
                          node.else_clause.type,
                          node.else_clause.location,
                          node.else_clause.errors,
                          node.else_clause.tag_opening,
                          node.else_clause.content,
                          node.else_clause.tag_closing,
                          extract_erb_nodes(node.else_clause.statements)
                        )
                      end

        ensure_clause = if node.ensure_clause
                          ::Herb::AST::ERBEnsureNode.new(
                            node.ensure_clause.type,
                            node.ensure_clause.location,
                            node.ensure_clause.errors,
                            node.ensure_clause.tag_opening,
                            node.ensure_clause.content,
                            node.ensure_clause.tag_closing,
                            extract_erb_nodes(node.ensure_clause.statements)
                          )
                        end

        ::Herb::AST::ERBBeginNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          extract_erb_nodes(node.statements),
          rescue_clause,
          else_clause,
          ensure_clause,
          node.end_node
        )
      end

      # @rbs rescue_node: ::Herb::AST::ERBRescueNode?
      def build_rescue_chain(rescue_node) #: ::Herb::AST::ERBRescueNode?
        return nil unless rescue_node

        ::Herb::AST::ERBRescueNode.new(
          rescue_node.type,
          rescue_node.location,
          rescue_node.errors,
          rescue_node.tag_opening,
          rescue_node.content,
          rescue_node.tag_closing,
          extract_erb_nodes(rescue_node.statements),
          build_rescue_chain(rescue_node.subsequent)
        )
      end

      # @rbs node: ::Herb::AST::ERBBlockNode
      def build_block_node(node) #: ::Herb::AST::ERBBlockNode
        ::Herb::AST::ERBBlockNode.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          extract_erb_nodes(node.body),
          node.end_node
        )
      end

      # Builds a loop node (for/while/until).
      # @rbs node: ::Herb::AST::Node
      def build_loop_node(node) #: ::Herb::AST::Node
        node.class.new(
          node.type,
          node.location,
          node.errors,
          node.tag_opening,
          node.content,
          node.tag_closing,
          extract_erb_nodes(node.statements),
          node.end_node
        )
      end
    end
  end
end
