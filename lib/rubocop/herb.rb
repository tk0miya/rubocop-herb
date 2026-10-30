# frozen_string_literal: true

require "not_nilable"

# NOTE: require_relative should be sorted in ASCII order
require_relative "herb/char_range"
require_relative "herb/comment_config"
require_relative "herb/configuration"
require_relative "herb/converter"
require_relative "herb/cop_correction_guard"
require_relative "herb/correction_adjuster"
require_relative "herb/correction_validator"
require_relative "herb/erb_location"
require_relative "herb/erb_node"
require_relative "herb/erb_parser"
require_relative "herb/escaped_erb_visitor"
require_relative "herb/extractor"
require_relative "herb/herb_lint_client"
require_relative "herb/immovable_expression_collector"
require_relative "herb/line_length_collector"
require_relative "herb/node_range"
require_relative "herb/parse_result"
require_relative "herb/plugin"
require_relative "herb/processed_source"
require_relative "herb/rubocop_ast_transformer"
require_relative "herb/ruby_comment"
require_relative "herb/ruby_renderer"
require_relative "herb/source"
require_relative "herb/trailing_whitespace_collector"
require_relative "herb/version"

require_relative "cop/herb/empty_erb_tag"
require_relative "cop/herb/linting"
require_relative "cop/herb/ignored_cop_directive"

module RuboCop
  module Herb
    # @rbs!
    #   # Union type for all ERB nodes
    #   type erb_node = ::Herb::AST::ERBIfNode
    #                 | ::Herb::AST::ERBUnlessNode
    #                 | ::Herb::AST::ERBElseNode
    #                 | ::Herb::AST::ERBCaseNode
    #                 | ::Herb::AST::ERBWhenNode
    #                 | ::Herb::AST::ERBCaseMatchNode
    #                 | ::Herb::AST::ERBInNode
    #                 | ::Herb::AST::ERBBeginNode
    #                 | ::Herb::AST::ERBRescueNode
    #                 | ::Herb::AST::ERBEnsureNode
    #                 | ::Herb::AST::ERBBlockNode
    #                 | ::Herb::AST::ERBForNode
    #                 | ::Herb::AST::ERBWhileNode
    #                 | ::Herb::AST::ERBUntilNode
    #                 | ::Herb::AST::ERBContentNode
    #                 | ::Herb::AST::ERBCommentNode
    #                 | ::Herb::AST::ERBEndNode
    #
    #   # Union type for all HTML nodes
    #   type html_node = ::Herb::AST::HTMLElementNode
    #                  | ::Herb::AST::HTMLTextNode
    #                  | ::Herb::AST::HTMLOpenTagNode
    #                  | ::Herb::AST::HTMLCloseTagNode
    #                  | ::Herb::AST::HTMLCommentNode
    #
    #   # Union type for ERB nodes holding the statements of a branch
    #   type branch_node = ::Herb::AST::ERBIfNode
    #                    | ::Herb::AST::ERBUnlessNode
    #                    | ::Herb::AST::ERBElseNode
    #                    | ::Herb::AST::ERBWhenNode
    #                    | ::Herb::AST::ERBInNode
    #                    | ::Herb::AST::ERBRescueNode

    class Error < StandardError; end
  end
end
