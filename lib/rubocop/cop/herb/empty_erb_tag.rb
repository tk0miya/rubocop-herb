# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for empty ERB tags (`<% %>`), which output nothing.
      #
      # An autocorrection removing the whole code of an ERB tag (e.g. `Lint/Void` removing `1` from `<% 1 %>`)
      # leaves an empty tag, as rubocop-herb keeps the delimiters of ERB tags.  This cop removes it,
      # along with its line if the tag is alone on the line, so that the code is removed as in Ruby files.
      # Otherwise the whitespace trimmed by the trim markers (the indentation before `<%-` and
      # the newline after `-%>`) is removed along with the tag, so the rendered output is kept.
      #
      # Output tags (`<%= %>`) and comments (`<%# %>`) are not checked.
      #
      # @example
      #   # bad
      #   <p>a</p>
      #   <% %>
      #   <p>b</p>
      #
      #   # good
      #   <p>a</p>
      #   <p>b</p>
      #
      #   # bad
      #   <p><% %></p>
      #
      #   # good
      #   <p></p>
      class EmptyErbTag < Base
        extend AutoCorrector

        MSG = "Remove the empty ERB tag."

        # Openings of the ERB tags checked by this cop (`<%=` and `<%==` are output tags)
        TAG_OPENINGS = ["<%", "<%-"].freeze #: Array[String]

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          source.parse_result.erb_locations.each_value do |location|
            node = location.node #: ::RuboCop::Herb::erb_node
            register_offense(node, source) if location.type == :content && empty_tag?(node)
          end
        end

        private

        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs source: ::RuboCop::Herb::ProcessedSource
        def register_offense(node, source) #: void
          tag = tag_range(node, source.parse_result)
          add_offense(Parser::Source::Range.new(source.buffer, tag.from, tag.to)) do |corrector|
            removal = removal_range(node, tag, source.parse_result)
            corrector.remove(Parser::Source::Range.new(source.buffer, removal.from, removal.to))
          end
        end

        # @rbs node: ::RuboCop::Herb::erb_node
        def empty_tag?(node) #: bool
          content = node.content
          !content.nil? && !node.tag_closing.nil? &&
            TAG_OPENINGS.include?(node.tag_opening&.value) && content.value.strip.empty?
        end

        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def tag_range(node, parse_result) #: ::RuboCop::Herb::CharRange
          range = ::Herb::Range.new(node.tag_opening.not_nil!.range.from, node.tag_closing.not_nil!.range.to)
          ::RuboCop::Herb::NodeRange.byte_range_to_char_range(range, parse_result.source)
        end

        # The range to remove for the tag
        # The line is removed if the tag is alone on it.  Otherwise the indentation before `<%-` and
        # the newline after `-%>` are removed as they are trimmed from the output
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs tag: ::RuboCop::Herb::CharRange
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def removal_range(node, tag, parse_result) #: ::RuboCop::Herb::CharRange
          line_from = line_range(tag.from, parse_result).first
          line_to = line_range(tag.to, parse_result).last
          if blank?(parse_result, line_from, tag.from) && blank?(parse_result, tag.to, line_to)
            return ::RuboCop::Herb::CharRange.new(line_from, line_to)
          end

          trimmed_range(node, tag, line_from, parse_result)
        end

        # The range of the tag and the whitespace trimmed by its trim markers
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs tag: ::RuboCop::Herb::CharRange
        # @rbs line_from: Integer -- start position of the line of the tag
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def trimmed_range(node, tag, line_from, parse_result) #: ::RuboCop::Herb::CharRange
          from = node.tag_opening&.value == "<%-" && blank?(parse_result, line_from, tag.from) ? line_from : tag.from
          to = node.tag_closing&.value == "-%>" && parse_result.code[tag.to] == "\n" ? tag.to + 1 : tag.to
          ::RuboCop::Herb::CharRange.new(from, to)
        end

        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        # @rbs from: Integer
        # @rbs to: Integer
        def blank?(parse_result, from, to) #: bool
          parse_result.slice(::RuboCop::Herb::CharRange.new(from, to)).strip.empty?
        end

        # The range of the line containing the position, including its newline
        # The newline itself belongs to the line it ends
        # @rbs pos: Integer
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def line_range(pos, parse_result) #: [Integer, Integer]
          offsets = parse_result.source.line_char_offsets
          index = (offsets.bsearch_index { _1 > pos } || offsets.size) - 1
          [offsets.fetch(index), offsets.fetch(index + 1, offsets.fetch(index))]
        end
      end
    end
  end
end
