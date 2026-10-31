# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for Ruby comments at the end of the code in ERB tags followed by ERB tags or HTML on the same line.
      #
      # ERB compiles a template into Ruby code keeping its lines, so such a comment comments out
      # the following ERB tags and HTML. The template outputs nothing for them,
      # or fails with a syntax error (e.g. when `<% end %>` is commented out).
      #
      # @example
      #   # bad
      #   <% name = user.name # the full name %><%= name %>
      #
      #   # good
      #   <% name = user.name # the full name %>
      #   <%= name %>
      #
      #   # good
      #   <% name = user.name %><%# the full name %><%= name %>
      class CommentedOutCode < Base
        MSG = "This Ruby comment comments out the ERB tags and HTML following it on the same line. " \
              "Place them on a separate line or use an ERB comment (`<%# %>`)."

        def on_new_investigation #: void
          investigate
        end

        # Investigate also a file with syntax errors (e.g. caused by `<% end %>` commented out),
        # for which RuboCop calls on_other_file instead of on_new_investigation
        def on_other_file #: void
          investigate
        end

        private

        def investigate #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          parse_result = source.parse_result
          parse_result.erb_locations.each_value do |location|
            next if location.comment?

            node = location.node #: ::RuboCop::Herb::erb_node
            next unless parse_result.followed_by_content?(node)

            range = ::RuboCop::Herb::RubyComment.trailing_range(node, parse_result.source)
            add_offense(Parser::Source::Range.new(source.buffer, range.from, range.to)) if range
          end
        end
      end
    end
  end
end
