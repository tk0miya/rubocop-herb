# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # CommentConfig subclass that disables cops at specific lines as if
    # `rubocop:disable` comments were written there.
    # This allows suppressing false positives caused by the ERB-to-Ruby conversion
    # only at the affected lines, instead of excluding the cops for whole files.
    #
    # Only #cop_enabled_at_lines? is overridden since #cop_enabled_at_line? delegates to it.
    # The disabled lines are not added to #cop_disabled_line_ranges
    # so that Lint/RedundantCopDisableDirective does not regard them as directive comments.
    class CommentConfig < ::RuboCop::CommentConfig
      attr_reader :disabled_cops #: Hash[String, Array[Range[Integer]]]

      # @rbs @disabled_lines: Hash[String, Set[Integer]]

      # @rbs processed_source: ::RuboCop::AST::ProcessedSource
      # @rbs disabled_cops: Hash[String, Array[Range[Integer]]] -- line ranges (1-based) where each cop is disabled
      def initialize(processed_source, disabled_cops: {}) #: void
        super(processed_source)
        @disabled_cops = disabled_cops
        @disabled_lines = {}
      end

      # Check only the first line: an offense range may span into a disabled line of another branch
      # (e.g. Lint/EmptyConditionalBody spans from `if` to the next `elsif`), hiding a truly empty branch.
      # @rbs cop: ::RuboCop::Cop::Base | String
      # @rbs first_line: Integer
      # @rbs last_line: Integer
      def cop_enabled_at_lines?(cop, first_line, last_line) #: bool
        cop_name = cop.is_a?(String) ? cop : cop.cop_name
        return false if disabled_lines(cop_name).include?(first_line)

        super
      end

      private

      # The lines where the cop is disabled
      # Converted from the line ranges once, as the cop is checked for each offense
      # @rbs cop_name: String
      def disabled_lines(cop_name) #: Set[Integer]
        @disabled_lines[cop_name] ||= disabled_cops.fetch(cop_name, []).each_with_object(Set.new) do |range, lines|
          lines.merge(range)
        end
      end
    end
  end
end
