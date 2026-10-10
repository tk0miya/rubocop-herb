# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    # Prepended to RuboCop::Cop::Base to discard autocorrections that would break ERB templates.
    # A discarded offense is reported as not autocorrectable.
    # Cops inspecting files other than ERB templates are not affected.
    module CopCorrectionGuard
      # @rbs!
      #   def processed_source: () -> ::RuboCop::AST::ProcessedSource?

      # `--disable-uncorrectable` inserts `# rubocop:todo` comments, which break ERB templates
      def disable_uncorrectable? #: bool
        return false if processed_source.is_a?(ProcessedSource)

        super
      end

      private

      # Keep it private as RuboCop::Cop::Base#correct is
      # @rbs range: ::Parser::Source::Range
      # @rbs &block: ? (::RuboCop::Cop::Corrector) -> void
      def correct(range, &block) #: [Symbol, ::RuboCop::Cop::Corrector?]
        source = processed_source
        return super unless block && source.is_a?(ProcessedSource)

        super do |corrector|
          # Correct on a candidate corrector first; the given corrector is left empty if rejected
          candidate = ::RuboCop::Cop::Corrector.new(corrector.source_buffer)
          block.call(candidate)
          corrector.merge!(candidate) if source.correction_validator.valid?(candidate)
        end
      end
    end
  end
end

RuboCop::Cop::Base.prepend(RuboCop::Herb::CopCorrectionGuard)
