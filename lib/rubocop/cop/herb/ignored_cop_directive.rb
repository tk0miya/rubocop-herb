# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for rubocop directives ignored by rubocop-herb because ERB tags follow them on the same line.
      #
      # rubocop-herb converts an ERB comment to a Ruby comment so that RuboCop processes it.
      # But rubocop-herb ignores an ERB comment followed by ERB tags on the same line,
      # because the Ruby comment would comment out the following code.
      # The same applies to a Ruby comment at the end of the code in an ERB tag (e.g. `<% x # comment %>`).
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
      #   # bad
      #   <% name = user.name # rubocop:disable Lint/UselessAssignment %><%= user.email %>
      #
      #   # good
      #   <% name = user.name # rubocop:disable Lint/UselessAssignment %>
      #   <%= user.email %>
      #
      #   # good (ordinary comments are not checked)
      #   <%# Show the user name %><%= user.name %>
      # rubocop:enable Lint/RedundantCopDisableDirective
      class IgnoredCopDirective < Base
        MSG = "rubocop-herb ignores this rubocop directive because ERB tags follow it on the same line. " \
              "Place them on a separate line."

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          parse_result = source.parse_result
          parse_result.erb_locations.each_value do |location|
            node = location.node #: ::RuboCop::Herb::erb_node
            next unless parse_result.followed_by_erb?(node)

            range = directive_range(node, parse_result)
            next unless range

            add_offense(Parser::Source::Range.new(source.buffer, range.from, range.to))
          end
        end

        private

        # Character range of the comment containing a rubocop directive in the ERB node:
        # the ERB comment itself, or the Ruby comment at the end of the code in the ERB tag
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def directive_range(node, parse_result) #: ::RuboCop::Herb::CharRange?
          if node.is_a?(::Herb::AST::ERBCommentNode)
            range = ::RuboCop::Herb::NodeRange.compute_char_range(node, parse_result.source)
            range if directive?(::RuboCop::Herb::RubyComment.render(node))
          else
            range = ::RuboCop::Herb::RubyComment.trailing_range(node, parse_result.source)
            range if range && directive?(parse_result.slice(range))
          end
        end

        # Whether the Ruby comment contains a rubocop directive (e.g. `rubocop:disable`)
        # @rbs comment: String
        def directive?(comment) #: bool
          DirectiveComment::DIRECTIVE_COMMENT_REGEXP.match?(comment)
        end
      end
    end
  end
end
