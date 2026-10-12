# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Checks for empty ERB tags (`<% %>`) and empty ERB comments (`<%# %>`), which output nothing.
      #
      # An autocorrection removing the whole code of an ERB tag (e.g. `Lint/Void` removing `1` from `<% 1 %>`)
      # leaves an empty tag, as rubocop-herb keeps the delimiters of ERB tags.  This cop removes it,
      # along with its line if the tag is alone on the line (or with other empty tags only),
      # so that the code is removed as in Ruby files.  If the tag ends the line after other content,
      # the whitespace before it is removed too, so as not to leave trailing whitespace.
      # Otherwise the whitespace trimmed by the trim markers (the indentation before `<%-` and
      # the newline after `-%>`) is removed along with the tag, so the rendered output is kept.
      #
      # Output tags (`<%= %>`) and literal tags (`<%% %>`) are not checked.
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
      #
      #   # bad
      #   <%# %>
      class EmptyErbTag < Base
        extend AutoCorrector

        MSG = "Remove the empty ERB tag."

        # Openings of the ERB tags checked by this cop
        # (`<%=` and `<%==` are output tags, and `<%%` is a literal tag outputting `<%`)
        TAG_OPENINGS = ["<%", "<%-", "<%#"].freeze #: Array[String]

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          nodes = source.parse_result.erb_locations.values.filter_map do |location|
            node = location.node #: ::RuboCop::Herb::erb_node
            node if (location.type == :content || location.comment?) && empty_tag?(node)
          end
          @empty_tags = nodes.map { tag_range(_1, source.parse_result) }.sort_by(&:from)
          nodes.each { register_offense(_1, source) }
        end

        private

        attr_reader :empty_tags #: Array[::RuboCop::Herb::CharRange] -- ranges of the empty tags in ascending order

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
        # The line is removed if the tag is alone on it or with other empty tags only (e.g. `<% %> <% %>`).
        # The whitespace before the tag is removed if the tag ends the line, unless `-%>` trims the newline,
        # so as not to leave trailing whitespace.
        # Otherwise the indentation before `<%-` and the newline after `-%>` are removed
        # as they are trimmed from the output
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs tag: ::RuboCop::Herb::CharRange
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def removal_range(node, tag, parse_result) #: ::RuboCop::Herb::CharRange
          line_from = line_range(tag.from, parse_result).first
          line_to = line_range(tag.to, parse_result).last
          ends_line = blank?(parse_result, tag.to, line_to)
          if ends_line && blank?(parse_result, line_from, tag.from)
            return ::RuboCop::Herb::CharRange.new(line_from, line_to)
          end
          if ends_line && !trims_newline?(node, tag, parse_result)
            return ::RuboCop::Herb::CharRange.new(whitespace_start(tag.from, line_from, parse_result), tag.to)
          end

          trimmed_range(node, tag, line_from, parse_result)
        end

        # The start position of the whitespace before the position in the line
        # @rbs pos: Integer
        # @rbs line_from: Integer -- start position of the line
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def whitespace_start(pos, line_from, parse_result) #: Integer
          whitespace = parse_result.slice(::RuboCop::Herb::CharRange.new(line_from, pos))[/[[:blank:]]*\z/].to_s
          pos - whitespace.length
        end

        # The range of the tag and the whitespace trimmed by its trim markers
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs tag: ::RuboCop::Herb::CharRange
        # @rbs line_from: Integer -- start position of the line of the tag
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def trimmed_range(node, tag, line_from, parse_result) #: ::RuboCop::Herb::CharRange
          # The indentation is trimmed only if it is whitespace, even if other empty tags precede the tag
          indented = parse_result.slice(::RuboCop::Herb::CharRange.new(line_from, tag.from)).strip.empty?
          from = node.tag_opening&.value == "<%-" && indented ? line_from : tag.from
          to = trims_newline?(node, tag, parse_result) ? tag.to + 1 : tag.to
          ::RuboCop::Herb::CharRange.new(from, to)
        end

        # Whether the trim marker `-%>` of the tag trims the newline after it
        # @rbs node: ::RuboCop::Herb::erb_node
        # @rbs tag: ::RuboCop::Herb::CharRange
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        def trims_newline?(node, tag, parse_result) #: bool
          node.tag_closing&.value == "-%>" && parse_result.code[tag.to] == "\n"
        end

        # Whether the range has only whitespace and empty tags, which are removed by this cop as well
        # @rbs parse_result: ::RuboCop::Herb::ParseResult
        # @rbs from: Integer
        # @rbs to: Integer
        def blank?(parse_result, from, to) #: bool
          pos = from
          empty_tags.each do |tag|
            next unless from <= tag.from && tag.to <= to
            return false unless parse_result.slice(::RuboCop::Herb::CharRange.new(pos, tag.from)).strip.empty?

            pos = tag.to
          end
          parse_result.slice(::RuboCop::Herb::CharRange.new(pos, to)).strip.empty?
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
