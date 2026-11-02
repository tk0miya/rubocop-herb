# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for Ruby comments at the end of the code in ERB tags (e.g. `<% x # comment %>`).
      #
      # ERB compiles a template into Ruby code keeping its lines, and appends code after the code of
      # each ERB tag, so such a comment comments out the code appended.
      # In an output tag (`<%=` and `<%==`), it comments out the code ERB appends to output the result,
      # so the template fails with a syntax error.
      # In other tags, it comments out the ERB tags and HTML placed after it on the same line:
      # the template outputs nothing for them, or fails with a syntax error (e.g. when `<% end %>` is commented out).
      # A comment followed by a newline in the tag (`%>` on the next line) is not reported.
      #
      # @example
      #   # bad
      #   <%= user.name # the full name %>
      #
      #   # bad
      #   <% name = user.name # the full name %><%= name %>
      #
      #   # bad (breaks when ERB tags or HTML are placed after it)
      #   <% name = user.name # the full name %>
      #
      #   # good
      #   <% name = user.name %><%# the full name %>
      #
      #   # good
      #   <% name = user.name # the full name
      #   %>
      class CommentedOutCode < Base
        OUTPUT_TAG_MSG = "Ruby code in an output tag should not end with a comment because it causes a syntax error. " \
                         "Use an ERB comment (`<%# %>`) or put `%>` on the next line."
        CODE_TAG_MSG = "Ruby code in an ERB tag should not end with a comment because it comments out " \
                       "any ERB tags and HTML placed after it on the same line. " \
                       "Use an ERB comment (`<%# %>`) or put `%>` on the next line."

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
            range = ::RuboCop::Herb::RubyComment.trailing_range(node, parse_result.source)
            next unless range

            add_offense(Parser::Source::Range.new(source.buffer, range.from, range.to), message: message(node))
          end
        end

        # The message for the ERB tag of the node
        # The tag opening is checked instead of the node type, as an output tag with a block
        # (e.g. `<%= form_with do |f| %>`) is a block node
        # @rbs node: ::RuboCop::Herb::erb_node
        def message(node) #: String
          output_tag = ::RuboCop::Herb::ErbLocation::OUTPUT_TAG_OPENINGS.include?(node.tag_opening&.value)
          output_tag ? OUTPUT_TAG_MSG : CODE_TAG_MSG
        end
      end
    end
  end
end
