# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Herb
    module Patch
      # Patch for RuboCop::Cop::Team to skip autocorrections that would rewrite HTML.
      # HTML parts are replaced with whitespace in the Ruby code, so a correction covering them
      # (e.g. replacing a whole `if` statement with its body) would remove the HTML from the ERB file.
      module Team
        private

        # @rbs report: untyped
        # @rbs &block: (::RuboCop::Cop::Corrector) -> void
        def each_corrector(report, &block) #: void
          processed_source = report.processed_source
          return super unless processed_source.is_a?(ProcessedSource)

          super do |corrector|
            block.call(corrector) unless rewrites_html?(corrector, processed_source.parse_result)
          end
        end

        # @rbs corrector: ::RuboCop::Cop::Corrector
        # @rbs parse_result: ParseResult
        def rewrites_html?(corrector, parse_result) #: bool
          corrector.as_replacements.any? do |range, _|
            parse_result.contains_html?(CharRange.new(range.begin_pos, range.end_pos))
          end
        end
      end
    end
  end
end

RuboCop::Cop::Team.prepend(RuboCop::Herb::Patch::Team)
