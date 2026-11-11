# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utilities for the branches of conditionals and rescue written across ERB tags
    module Branches
      module_function

      # The if branch, the elsif branches and the else branch
      # @rbs node: ::Herb::AST::ERBIfNode
      def of_if(node) #: Array[branch_node]
        branches = [] #: Array[branch_node]
        branch = node #: branch_node?
        while branch
          branches << branch
          branch = branch.is_a?(::Herb::AST::ERBIfNode) ? branch.subsequent : nil
        end
        branches
      end

      # The rescue clauses and the else clause, which are the branches of rescue in the Ruby code
      # @rbs node: ::Herb::AST::ERBBeginNode | ::Herb::AST::ERBBlockNode
      def of_rescue(node) #: Array[branch_node]
        branches = [] #: Array[branch_node]
        rescue_clause = node.rescue_clause
        while rescue_clause
          branches << rescue_clause
          rescue_clause = rescue_clause.subsequent
        end
        else_clause = node.else_clause
        branches << else_clause if else_clause
        branches
      end

      # Check if the nodes contain HTML not rendered in the Ruby code (except whitespace):
      # text and literals too short to place the marker (see RubyRenderer.text_marker_position),
      # attributes in ERB nodes none of whose literals fit the marker (see RubyRenderer#visit_html_attribute_node),
      # and comments, doctypes, CDATA and XML declarations containing ERB (except escaped ERB tags, which are text)
      # none of whose literals fit the marker (their literals are rendered instead of them,
      # see RubyRenderer#render_opening_node)
      # ERB nodes are checked recursively because their bodies (e.g. nested conditionals and blocks) are a part of
      # the branch, and so are the ones in attributes, comments and so on. HTML elements and tags are not
      # because they are rendered and make the branch unique.
      # @rbs nodes: Array[::Herb::AST::Node]
      def unrendered_html?(nodes) #: bool
        nodes.any? { unrendered_html_node?(_1) }
      end

      # @rbs node: ::Herb::AST::Node
      def unrendered_html_node?(node) #: bool
        case node
        when ::Herb::AST::HTMLTextNode, ::Herb::AST::LiteralNode
          unrendered_text?(node.content.to_s)
        when ::Herb::AST::HTMLElementNode, ::Herb::AST::HTMLOpenTagNode, ::Herb::AST::HTMLCloseTagNode,
             ::Herb::AST::WhitespaceNode
          false
        when ::Herb::AST::HTMLAttributeNode
          unrendered_attribute?(node)
        when ::Herb::AST::HTMLCommentNode, ::Herb::AST::HTMLDoctypeNode, ::Herb::AST::CDATANode,
             ::Herb::AST::XMLDeclarationNode
          unrendered_opening_node?(node)
        else
          node.type.start_with?("AST_ERB_") ? unrendered_html?(node.compact_child_nodes) : true
        end
      end

      # @rbs text: String
      def unrendered_text?(text) #: bool
        text.match?(/\S/) && !RubyRenderer.text_marker_position(text)
      end

      # Check if the attribute in an ERB node has no literal to place the marker in (e.g. `id="ab"` and
      # `<%= k %>="<%= v %>"`), or contains ERB nodes with HTML not rendered (e.g. `class="<% if a %>x<% end %>"`)
      # The marker of the attribute is rendered at one of its literals (see RubyRenderer#visit_html_attribute_node),
      # so its other literals are not checked
      # @rbs node: ::Herb::AST::HTMLAttributeNode
      def unrendered_attribute?(node) #: bool
        children = [*node.name&.children, *node.value&.children] #: Array[::Herb::AST::Node]
        no_marker?(children) || unrendered_html?(children.grep_v(::Herb::AST::LiteralNode))
      end

      # Check if the comment, doctype, CDATA or XML declaration containing ERB has no literal to place the marker in
      # (its delimiters, e.g. `<!--`, are not rendered), or contains HTML not rendered
      # A comment and so on without ERB is rendered at its opening
      # @rbs node: html_opening_node
      def unrendered_opening_node?(node) #: bool
        with_erb?(node) && (no_marker?(node.children) || unrendered_html?(node.children))
      end

      # Check if none of the literals in the nodes fits the marker
      # @rbs nodes: Array[::Herb::AST::Node]
      def no_marker?(nodes) #: bool
        nodes.none? { _1.is_a?(::Herb::AST::LiteralNode) && RubyRenderer.marker_fits?(_1) }
      end

      # Check if the comment, doctype, CDATA or XML declaration contains ERB
      # (except escaped ERB tags, which are text)
      # @rbs node: html_opening_node
      def with_erb?(node) #: bool
        node.children.any? { _1.type.start_with?("AST_ERB_") && !ErbNode.escaped?(_1) }
      end
    end
  end
end
