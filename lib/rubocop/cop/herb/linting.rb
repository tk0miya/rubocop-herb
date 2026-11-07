# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Herb
      # Runs herb-lint (@herb-tools/linter) on HTML+ERB files and reports its offenses.
      #
      # This cop requires Node.js and @herb-tools/linter installed in the project
      # (`npm install --save-dev @herb-tools/linter`).
      # If herb-lint is not available, an offense asking to set it up or disable this cop is reported
      # (reported once, not for every file).
      # herb-lint is configured by `.herb.yml` in the project root as usual.
      #
      # The offenses autocorrectable by herb-lint (`herb-lint --fix`) are autocorrected by `rubocop -a`.
      # The unsafe ones (`herb-lint --fix-unsafely`) are autocorrected only by `rubocop -A`.
      #
      # @example
      #   # bad
      #   <img src="logo.png">
      #
      #   # good
      #   <img src="logo.png" alt="Logo">
      class Linting < Base
        include ::RuboCop::Herb::HerbToolCop
        extend AutoCorrector

        SEVERITIES = {
          "error" => :error,
          "warning" => :warning,
          "info" => :convention,
          "hint" => :refactor
        }.freeze #: Hash[String, Symbol]

        # Rules of herb-lint not reported, as other Herb cops report the same offenses with autocorrection
        REPLACED_RULES = [
          "erb-no-empty-tags" # Herb/EmptyErbTag
        ].freeze #: Array[String]

        # Files affecting the result of herb-lint other than the linted file itself
        CONFIG_FILES = [
          ".herb.yml",
          "node_modules/@herb-tools/linter/package.json",
          ".herb/rules/**/*.{js,mjs}"
        ].freeze #: Array[String]

        def on_new_investigation #: void
          source = processed_source
          return unless source.is_a?(::RuboCop::Herb::ProcessedSource)

          path = source.file_path
          return unless path

          lint(source, File.expand_path(path))
        end

        private

        attr_reader :options #: Hash[Symbol, untyped] -- options of RuboCop; Base has no reader for them

        # @rbs source: ::RuboCop::Herb::ProcessedSource
        # @rbs path: String -- absolute path of the file
        def lint(source, path) #: void
          # The fixes applied so far in this investigation
          applied = ::RuboCop::Cop::Corrector.new(source.buffer)
          herb_lint_offenses(source, path).each { report(_1, applied) }
        rescue ::RuboCop::Herb::HerbLintClient::StartupError => e
          report_startup_error(client, path, e, tool: "herb-lint", package: "@herb-tools/linter")
        end

        # Reports the offense of herb-lint with its fix
        # @rbs offense: ::RuboCop::Herb::HerbLintClient::Offense
        # @rbs applied: ::RuboCop::Cop::Corrector -- the fixes applied so far
        def report(offense, applied) #: void
          add_offense_at(offense_range(offense), "[#{offense.rule}] #{offense.message}",
                         SEVERITIES.fetch(offense.severity, :convention)) do |corrector|
            fix = offense.fix
            correct_with(corrector, fix, applied) if fix
          end
        end

        # Offenses of herb-lint except the rules replaced by other Herb cops
        # @rbs source: ::RuboCop::Herb::ProcessedSource
        # @rbs path: String -- absolute path of the file
        def herb_lint_offenses(source, path) #: Array[::RuboCop::Herb::HerbLintClient::Offense]
          client.lint(path, source.parse_result.code, unsafe_fixes: unsafe_fixes?)
                .reject { REPLACED_RULES.include?(_1.rule) }
        end

        # Whether to fix offenses with the unsafe fixes of herb-lint (`herb-lint --fix-unsafely`).
        # They are applied by `rubocop -A` but not by `rubocop -a`, as the unsafe corrections of RuboCop cops are.
        # Without autocorrection, they mark the offenses correctable (e.g. for quick fixes of `rubocop --lsp`).
        def unsafe_fixes? #: bool
          !options.fetch(:safe_autocorrect, false)
        end

        def client #: ::RuboCop::Herb::HerbLintClient
          ::RuboCop::Herb::HerbLintClient.for(node_command:, project_root:, checksum: external_dependency_checksum)
        end

        def config_files #: Array[String]
          CONFIG_FILES
        end

        def server_scripts #: Array[String]
          ::RuboCop::Herb::HerbLintClient.server_scripts
        end

        # @rbs offense: ::RuboCop::Herb::HerbLintClient::Offense
        def offense_range(offense) #: Parser::Source::Range
          buffer = processed_source.buffer
          begin_pos = position(buffer, offense.start_line, offense.start_column)
          end_pos = position(buffer, offense.end_line, offense.end_column)
          end_pos = begin_pos if end_pos < begin_pos
          Parser::Source::Range.new(buffer, begin_pos, end_pos)
        end

        # @rbs buffer: Parser::Source::Buffer
        # @rbs line: Integer -- 1-based line number
        # @rbs column: Integer -- 0-based column number
        def position(buffer, line, column) #: Integer
          line = line.clamp(1, buffer.last_line)
          line_range = buffer.line_range(line)
          (line_range.begin_pos + column).clamp(line_range.begin_pos, line_range.end_pos)
        end
      end
    end
  end
end
