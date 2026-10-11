# frozen_string_literal: true

require "herb"

module RuboCop
  module Herb
    # Utility module for rendering ERB comments as Ruby comments
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
    end
  end
end
