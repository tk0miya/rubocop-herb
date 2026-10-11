# frozen_string_literal: true

require "herb"
require "prism"

module RuboCop
  module Herb
    # Utility module for Ruby comments in ERB: rendering ERB comments as Ruby comments,
    # and finding Ruby comments in the code of ERB tags
    module RubyComment
      # Render an ERB comment to a Ruby comment (from "#" of "<%#" to the end of the content)
      # Each line of a multiline comment is commented out with "#"
      # @rbs node: ::Herb::AST::ERBCommentNode
      def self.render(node) #: String
        hash_column = node.tag_opening.not_nil!.location.start.column + 2
        "##{format_multiline_comment(node.content.not_nil!.value, hash_column)}"
      end

      # @rbs code: String
      # @rbs hash_column: Integer
      def self.format_multiline_comment(code, hash_column) #: String
        result = code.gsub(/(?<=\n)( +)/) do |match|
          if match.length > hash_column + 1
            "#{match[0...hash_column]}##{match[(hash_column + 1)..]}"
          else
            "##{match[1..]}"
          end
        end

        result.gsub(/(?<=\n)([^ \n#])/, "#")
      end
      private_class_method :format_multiline_comment

      # Character range of the Ruby comment at the end of the code in the ERB tag (e.g. `<% x # comment %>`)
      # A comment followed by a newline (e.g. `%>` on its own line) is not a trailing comment
      # @rbs node: erb_node
      # @rbs source: Source
      def self.trailing_range(node, source) #: CharRange?
        content = node.content
        return unless content

        comment = trailing_comment(content.value)
        return unless comment

        from = source.byte_to_char_pos(content.range.from)
        CharRange.new(from + comment.start_character_offset, from + comment.end_character_offset)
      end

      # Location of the Ruby comment at the end of the code, followed only by spaces on the same line
      # @rbs code: String
      def self.trailing_comment(code) #: Prism::Location?
        location = Prism.parse_comments(code).last&.location
        location if location && code.byteslice(location.end_offset..).to_s.match?(/\A[ \t]*\z/)
      end
      private_class_method :trailing_comment
    end
  end
end
