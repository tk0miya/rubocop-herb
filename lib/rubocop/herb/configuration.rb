# frozen_string_literal: true

module RuboCop
  module Herb
    # Configuration module for managing supported extensions.
    module Configuration
      DEFAULT_EXTENSIONS = %w[.html.erb].freeze #: Array[String]

      # Cops to exclude from ERB files due to inherent incompatibilities
      # with extracted Ruby code from ERB templates.
      EXCLUDED_COPS = [
        "Layout/CommentIndentation", # ERB comment to Ruby comment conversion shifts column position
        "Layout/EndAlignment", # Ruby end keywords in ERB may align with HTML structure, not Ruby
        "Layout/ExtraSpacing", # Whitespace padding preserves positions but creates extra spaces
        "Layout/IndentationConsistency", # Ruby code in ERB may be aligned differently
        "Layout/IndentationWidth", # Ruby code in ERB may have different indentation width
        "Layout/InitialIndentation", # ERB code may start at any indentation level within HTML
        "Layout/LeadingEmptyLines", # ERB files may not start with Ruby code
        "Layout/TrailingEmptyLines", # ERB files may not end with Ruby code
        "Layout/TrailingWhitespace", # Whitespace padding preserves positions but creates trailing spaces
        "Style/BlockDelimiters", # ERB blocks often use do/end across multiple tags
        "Style/FrozenStringLiteralComment", # ERB files don't support frozen string literal comments
        "Style/IfUnlessModifier", # Single-line ERB conditionals cannot be converted to modifier form
        "Style/IfWithSemicolon", # Semicolons are inserted between ERB tags on the same line
        "Style/Semicolon" # Semicolons are inserted between ERB tags on the same line
      ].freeze #: Array[String]

      # Cops excluded due to HTML visualization limitations.
      # These cops produce false positives even with HTML visualization enabled.
      HTML_RELATED_EXCLUDED_COPS = [
        "Layout/EmptyLineAfterGuardClause", # Guard clause followed by HTML appears as empty line
        "Style/IdenticalConditionalBranches", # Same tag names in different branches appear identical
        "Style/Next", # Loop conditions may guard HTML output, not suitable for next
        "Style/RedundantCondition" # Ternary operators like `foo ? foo : bar` are flagged regardless of context
      ].freeze #: Array[String]

      # @rbs self.@supported_extensions: Array[String]
      # @rbs self.@html_visualization: bool

      class << self
        # @rbs config: Hash[String, untyped]
        def setup(config) #: void
          @supported_extensions = config["extensions"] || DEFAULT_EXTENSIONS
          @html_visualization = config["html_visualization"] || false
        end

        def html_visualization? #: bool
          @html_visualization
        end

        # @rbs path: String
        def supported_file?(path) #: bool
          @supported_extensions.any? { |ext| path.end_with?(ext) }
        end

        def to_rubocop_config #: Hash[String, untyped]
          # Include both relative and absolute path patterns for glob matching
          globs = @supported_extensions.flat_map { |ext| ["**/*#{ext}", "/**/*#{ext}"] }

          config = { "AllCops" => { "Include" => globs } }
          (EXCLUDED_COPS + HTML_RELATED_EXCLUDED_COPS).each do |cop|
            config[cop] = { "Exclude" => globs }
          end
          config
        end
      end
    end
  end
end
