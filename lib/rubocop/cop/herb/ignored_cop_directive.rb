# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for rubocop directives in ERB comments ignored by rubocop-herb
      # because ERB tags or HTML follow them on the same line.
      #
      # rubocop-herb converts an ERB comment to a Ruby comment so that RuboCop processes it.
      # But rubocop-herb ignores an ERB comment followed by ERB tags or HTML on the same line,
      # because the Ruby comment would comment out the following code.
      # This is harmless for ordinary comments, but rubocop directives (e.g. `rubocop:disable`)
      # in such a comment have no effect.
      #
      # rubocop:disable Lint/RedundantCopDisableDirective -- the examples contain directives
      # @example
      #   # bad
      #   <%# rubocop:disable Lint/Void %><%= user.name %>
      #
      #   # good
      #   <%# rubocop:disable Lint/Void %>
      #   <%= user.name %>
      #
      #   # good
      #   <%= user.name %><%# rubocop:disable Lint/Void %>
      #
      #   # good (ordinary comments are not checked)
      #   <%# Show the user name %><%= user.name %>
      # rubocop:enable Lint/RedundantCopDisableDirective
      class IgnoredCopDirective < Base
        MSG = "rubocop-herb ignores this rubocop directive because ERB tags or HTML follow it on the same line. " \
              "Place them on a separate line."

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          parse_result = source.parse_result
          parse_result.erb_comment_nodes.each do |node|
            next unless parse_result.followed_by_content?(node)
            next unless directive?(::RuboCop::Herb::RubyComment.render(node))

            range = ::RuboCop::Herb::NodeRange.compute_char_range(node, parse_result.source)
            add_offense(Parser::Source::Range.new(source.buffer, range.from, range.to))
          end
        end

        private

        # Whether the ERB comment rendered as a Ruby comment contains a rubocop directive (e.g. `rubocop:disable`)
        # @rbs comment: String
        def directive?(comment) #: bool
          DirectiveComment::DIRECTIVE_COMMENT_REGEXP.match?(comment)
        end
      end
    end
  end
end
