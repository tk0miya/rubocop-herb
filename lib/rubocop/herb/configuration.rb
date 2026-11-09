# frozen_string_literal: true

module RuboCop
  module Herb
    # Configuration of rubocop-herb: the supported extensions, the cops excluded or filtered in ERB files,
    # and the default configuration of the Herb cops.
    #
    # rubocop-herb lints the Ruby code in ERB tags; the layout of HTML and text (blank lines and whitespace
    # outside ERB tags) is left to herb-lint and herb-format. The cops excluded or filtered for this reason
    # name the corresponding herb-lint rule, or "no herb-lint rule" when herb-lint has none.
    module Configuration
      DEFAULT_EXTENSIONS = %w[.html.erb].freeze #: Array[String]

      # Cops to exclude from ERB files due to inherent incompatibilities
      # with extracted Ruby code from ERB templates.
      EXCLUDED_COPS = [
        "Layout/CommentIndentation", # ERB comment to Ruby comment conversion shifts column position
        # The blank line after a magic comment in an ERB comment is in HTML and text (no herb-lint rule;
        # herb-format removes it, which makes the autocorrection loop infinitely)
        "Layout/EmptyLineAfterMagicComment",
        "Layout/InitialIndentation", # ERB code may start at any indentation level within HTML
        "Layout/LeadingEmptyLines", # Blank lines at the start of the file are in HTML and text (no herb-lint rule)
        # Blank lines at the end of the file are in HTML and text (herb-lint: erb-require-trailing-newline)
        "Layout/TrailingEmptyLines",
        "Metrics/BlockLength", # ERB blocks often contain substantial HTML content
        "Naming/FileName", # ERB file names may contain locales or variants (e.g. show.en-US.html.erb)
        "Style/FrozenStringLiteralComment" # ERB files don't support frozen string literal comments
      ].freeze #: Array[String]

      # Cops reporting the code rendered by the conversion (HTML, the delimiters of ERB tags and semicolons
      # rendered at their closings), which are disabled except for the code copied verbatim from ERB tags
      # (see VerbatimCode and CopOffenseFilter)
      VERBATIM_CODE_COPS = [
        "Layout/BlockEndNewline", # HTML before the end tag is rendered as an expression before `end`
        "Layout/EmptyComment", # The first line of a multi-line ERB comment is rendered as an empty comment
        "Layout/EmptyLines", # Blank lines between ERB tags are in HTML and text (herb-lint: erb-no-extra-newline)
        # Blank lines between ERB tags are in HTML and text (no herb-lint rule)
        "Layout/EmptyLinesAroundArguments",
        "Layout/EmptyLinesAroundBeginBody",
        "Layout/EmptyLinesAroundBlockBody",
        "Layout/EmptyLinesAroundClassBody",
        "Layout/EmptyLinesAroundExceptionHandlingKeywords",
        "Layout/EmptyLinesAroundMethodBody",
        "Layout/EmptyLinesAroundModuleBody",
        "Layout/ExtraSpacing", # The delimiters of ERB tags and HTML are rendered as whitespace
        "Layout/SpaceAroundOperators", # The tag opening of an output tag is rendered as `_ =`
        # The closing delimiters of ERB tags are rendered as whitespace,
        # and trailing whitespace in HTML and text is left to herb-lint (erb-no-trailing-whitespace)
        "Layout/TrailingWhitespace",
        "Lint/ElseLayout", # A semicolon is rendered at the closing of the else tag (`else;  _ = x;`)
        "Style/ConditionalAssignment", # Output tags in the branches are all rendered as `_ = ...`
        "Style/IfWithSemicolon", # A semicolon is rendered at the closing of the if tag (`if a;`)
        "Style/InPatternThen", # A semicolon is rendered at the closing of the in tag (`in 1;`)
        "Style/OneLineConditional", # Conditionals across ERB tags on a single line become `if a; ...; end`
        "Style/RedundantCondition", # Output tags in the branches are rendered as `_ = a` (`if a; _ = a; ...`)
        "Style/Semicolon", # Semicolons are rendered between ERB tags on the same line
        "Style/SingleLineDoEndBlock", # Blocks across ERB tags on a single line become `foo do ...; end`
        "Style/WhenThen" # A semicolon is rendered at the closing of the when tag (`when 1;`)
      ].freeze #: Array[String]

      # Cops whose autocorrection is discarded in ERB files
      UNCORRECTABLE_COPS = [
        "Style/Semicolon" # It breaks the line at the semicolon without indenting the next statement
      ].freeze #: Array[String]

      class << self
        # @rbs config: Hash[String, untyped]
        def setup(config) #: void
          @supported_extensions = config["extensions"] || DEFAULT_EXTENSIONS
        end

        # @rbs path: String
        def supported_file?(path) #: bool
          supported_extensions.any? { path.end_with?(_1) }
        end

        def to_rubocop_config #: Hash[String, untyped]
          # Include both relative and absolute path patterns for glob matching
          globs = supported_extensions.flat_map { ["**/*#{_1}", "/**/*#{_1}"] }

          config = {
            "AllCops" => { "Include" => globs },
            "Herb/Linting" => herb_lint_config(globs),
            "Herb/Formatting" => herb_format_config(globs),
            "Herb/IgnoredCopDirective" => ignored_cop_directive_config(globs),
            "Herb/EmptyErbTag" => empty_erb_tag_config(globs)
          }
          EXCLUDED_COPS.each do |cop|
            config[cop] = { "Exclude" => globs }
          end
          config
        end

        private

        # Default configuration of Herb/Linting cop (enabled; it reports an error if herb-lint is not set up)
        # @rbs globs: Array[String]
        def herb_lint_config(globs) #: Hash[String, untyped]
          {
            "Description" => "Runs herb-lint (@herb-tools/linter) on HTML+ERB files.",
            "Enabled" => true,
            "Include" => globs,
            "NodeCommand" => "node"
          }
        end

        # Default configuration of Herb/Formatting cop.
        # It is enabled, but does nothing unless the formatter is enabled in .herb.yml (`formatter.enabled`).
        # The autocorrection is unsafe as herb-format is in experimental preview and changes the whitespace in HTML
        # @rbs globs: Array[String]
        def herb_format_config(globs) #: Hash[String, untyped]
          {
            "Description" => "Checks that HTML+ERB files are formatted by herb-format (@herb-tools/formatter) " \
                             "if the formatter is enabled in .herb.yml.",
            "Enabled" => true,
            "SafeAutoCorrect" => false,
            "Include" => globs,
            "NodeCommand" => "node"
          }
        end

        # Default configuration of Herb/IgnoredCopDirective cop
        # @rbs globs: Array[String]
        def ignored_cop_directive_config(globs) #: Hash[String, untyped]
          {
            "Description" => "Checks for rubocop directives in ERB comments ignored by rubocop-herb " \
                             "because ERB tags or HTML follow them on the same line.",
            "Enabled" => true,
            "Include" => globs
          }
        end

        # Default configuration of Herb/EmptyErbTag cop
        # @rbs globs: Array[String]
        def empty_erb_tag_config(globs) #: Hash[String, untyped]
          {
            "Description" => "Checks for empty ERB tags, which output nothing.",
            "Enabled" => true,
            "Include" => globs
          }
        end

        # rbs-inline emits attr_reader as an instance reader regardless of
        # nesting inside `class << self`, so declare the singleton reader by hand.
        # @rbs skip
        attr_reader :supported_extensions #: Array[String]

        # @rbs!
        #   private attr_reader self.supported_extensions: Array[String]
      end
    end
  end
end
