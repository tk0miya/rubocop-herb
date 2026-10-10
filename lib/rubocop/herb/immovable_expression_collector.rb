# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Collects the lines where Style/IdenticalConditionalBranches should be disabled.
    # The cop suggests moving an expression shared by all branches out of the conditional,
    # but an expression next to HTML cannot be moved without changing the output
    # (e.g. `x` in `<div><%= x %></div>` or `<input <%= x %>>`).
    # Such expressions are found from the Ruby AST and the HTML in the original source.
    class ImmovableExpressionCollector
      COP_NAME = "Style/IdenticalConditionalBranches" #: String

      # Tokens that are not expressions (newlines, semicolons and comments)
      SKIPPED_TOKEN_TYPES = %i[tNL tSEMI tCOMMENT].freeze #: Array[Symbol]

      # Collect the disabled lines from a processed source
      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def self.collect(processed_source, parse_result) #: Hash[String, Array[Range[Integer]]]
        new(processed_source, parse_result).collect
      end

      attr_reader :ast #: ::RuboCop::AST::Node?
      attr_reader :tokens #: Array[::RuboCop::AST::Token]
      attr_reader :parse_result #: ParseResult
      attr_reader :erb_tag_ranges #: Array[CharRange]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs parse_result: ParseResult
      def initialize(processed_source, parse_result) #: void
        @ast = processed_source.ast
        @tokens = processed_source.tokens.reject { SKIPPED_TOKEN_TYPES.include?(_1.type) }
        @parse_result = parse_result
        @erb_tag_ranges = parse_result.erb_tag_ranges
      end

      # Only the first line of each expression is disabled, which is enough to suppress the offense
      # at the expression, so that offenses inside a multi-line expression are still reported
      def collect #: Hash[String, Array[Range[Integer]]]
        lines = [] #: Array[Range[Integer]]
        ast&.each_node(:if, :case, :case_match) do |node|
          branches = branches(node)
          lines.concat(immovable_expressions(branches).map { _1.first_line.._1.first_line }) if branches.any?
        end
        lines.empty? ? {} : { COP_NAME => lines }
      end

      private

      # Identical tails (or heads) of the branches that cannot be moved after (or before) the conditional
      # An expression that is both a tail and a head (a branch having a single expression) is immovable
      # only if it can be moved in neither direction
      # (the direction of the autocorrection is not considered; it is unsafe and does not work for ERB anyway)
      # @rbs branches: Array[::RuboCop::AST::Node]
      def immovable_expressions(branches) #: Array[::RuboCop::AST::Node]
        immovable_tails, movable_tails = split_by_movability(tails(branches)) { html_after?(_1) }
        immovable_heads, movable_heads = split_by_movability(heads(branches)) { html_before?(_1) }
        movable = movable_tails + movable_heads
        (immovable_tails + immovable_heads).uniq(&:object_id).reject { |node| movable.any? { _1.equal?(node) } }
      end

      # Split identical expressions into immovable ones and movable ones
      # The expressions are immovable if HTML is next to any of them
      # Expressions that are not identical are neither, because the cop does not report them
      # @rbs expressions: Array[::RuboCop::AST::Node]
      # @rbs &: (::RuboCop::AST::Node) -> bool -- checks if HTML is next to the expression
      def split_by_movability(expressions, &) #: [Array[::RuboCop::AST::Node], Array[::RuboCop::AST::Node]]
        return [[], []] unless expressions.uniq.one?

        expressions.any?(&) ? [expressions, []] : [[], expressions]
      end

      # Last expressions of the branches
      # @rbs branches: Array[::RuboCop::AST::Node]
      def tails(branches) #: Array[::RuboCop::AST::Node]
        branches.map { _1.begin_type? ? _1.children.last : _1 }
      end

      # First expressions of the branches
      # @rbs branches: Array[::RuboCop::AST::Node]
      def heads(branches) #: Array[::RuboCop::AST::Node]
        branches.map { _1.begin_type? ? _1.children.first : _1 }
      end

      # Branches compared by Style/IdenticalConditionalBranches
      # Returns an empty array if the conditional has a branch without expressions (including a missing else)
      # @rbs node: ::RuboCop::AST::Node
      def branches(node) #: Array[::RuboCop::AST::Node]
        branches = case node
                   when ::RuboCop::AST::IfNode then if_branches(node)
                   when ::RuboCop::AST::CaseNode then [*node.when_branches.map(&:body), node.else_branch]
                   when ::RuboCop::AST::CaseMatchNode then [*node.in_pattern_branches.map(&:body), node.else_branch]
                   else [] #: Array[::RuboCop::AST::Node?]
                   end
        branches.all? ? branches.compact : []
      end

      # @rbs node: ::RuboCop::AST::IfNode
      def if_branches(node) #: Array[::RuboCop::AST::Node?]
        return [] if node.elsif? # elsif nodes are checked as a part of the outer if node

        branches = [node.if_branch]
        else_branch = node.else_branch
        while else_branch.is_a?(::RuboCop::AST::IfNode) && else_branch.elsif?
          branches << else_branch.if_branch
          else_branch = else_branch.else_branch
        end
        branches << else_branch
      end

      # Check if HTML follows the expression in its branch
      # @rbs node: ::RuboCop::AST::Node
      def html_after?(node) #: bool
        from = node.source_range.end_pos
        next_token = tokens.bsearch { _1.begin_pos >= from }
        html_between?(from, next_token&.begin_pos || parse_result.code.length)
      end

      # Check if HTML precedes the expression in its branch
      # @rbs node: ::RuboCop::AST::Node
      def html_before?(node) #: bool
        to = node.source_range.begin_pos
        index = tokens.bsearch_index { _1.end_pos > to } || tokens.size
        html_between?(index.positive? ? tokens[index - 1].not_nil!.end_pos : 0, to)
      end

      # Check if the original source contains HTML (non-whitespace characters outside of ERB tags) in the range
      # @rbs from: Integer
      # @rbs to: Integer
      def html_between?(from, to) #: bool
        parse_result.code[from...to].to_s.each_char.with_index(from).any? do |char, pos|
          char.match?(/\S/) && !erb_tag?(pos)
        end
      end

      # @rbs pos: Integer
      def erb_tag?(pos) #: bool
        range = erb_tag_ranges.bsearch { _1.to > pos }
        !range.nil? && range.from <= pos
      end
    end
  end
end
