# frozen_string_literal: true

require "digest/sha1"
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

        # Invalidates the result cache when Node.js, herb-lint, its configuration, or custom rules change
        def external_dependency_checksum #: String
          files = CONFIG_FILES.flat_map { Dir.glob(_1, base: project_root) }.sort
          contents = files.map { "#{_1}\n#{File.read(File.join(project_root, _1))}" }
          Digest::SHA1.hexdigest([node_command, node_path.to_s, File.read(::RuboCop::Herb::HerbLintClient::SERVER_SCRIPT),
                                  *contents].join("\n"))
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
          # Do not consume the report on a file where it would be suppressed by a disable comment
          return unless source.comment_config.cop_enabled_at_line?(self, 1)
          return unless client.report_startup_error_on?(path)

          add_offense_at(source.buffer.line_range(1),
                         "herb-lint is not available: #{e.message}. Set up herb-lint " \
                         "(`npm install --save-dev @herb-tools/linter`) or disable Herb/Linting cop.",
                         :error)
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

        # Adds an offense at the range, or to the whole file if the file is empty
        # Formatters fail to read the source line of an offense in an empty file, so Lint/EmptyFile also
        # reports a global offense for it
        # @rbs range: Parser::Source::Range
        # @rbs message: String
        # @rbs severity: Symbol
        # @rbs &block: ? (::RuboCop::Cop::Corrector) -> void
        def add_offense_at(range, message, severity, &block) #: void
          if processed_source.buffer.source.empty?
            add_global_offense(message, severity:)
          elsif block # Steep does not accept passing a nil block to add_offense
            add_offense(range, message:, severity:, &block)
          else
            add_offense(range, message:, severity:)
          end
        end

        # Corrects the source with the fix of herb-lint.
        # herb-lint fixes each offense on the source as it is, so the fixes of the offenses may overlap
        # (e.g. both the opening and closing tags of an element are replaced to fix the case of its name).
        # A fix clobbering the fixes applied before is skipped (the offense is reported as not corrected),
        # and is applied in the next iteration of autocorrection, where herb-lint reports it again if it remains.
        # @rbs corrector: ::RuboCop::Cop::Corrector
        # @rbs fix: ::RuboCop::Herb::HerbLintClient::Fix
        # @rbs applied: ::RuboCop::Cop::Corrector -- the fixes applied so far
        def correct_with(corrector, fix, applied) #: void
          buffer = corrector.source_buffer
          return unless fix.end_pos <= buffer.source.length

          candidate = ::RuboCop::Cop::Corrector.new(buffer)
          candidate.replace(Parser::Source::Range.new(buffer, fix.begin_pos, fix.end_pos), fix.replacement)
          # Corrections are applied only when autocorrecting; otherwise they only mark offenses as correctable
          applied.merge!(candidate) if autocorrect?
          corrector.merge!(candidate)
        rescue ::Parser::ClobberingError
          nil
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

        def node_command #: String
          cop_config.fetch("NodeCommand", "node")
        end

        # The path of the Node.js executable; nil if not installed
        def node_path #: String?
          candidates = if node_command.include?(File::SEPARATOR)
                         [node_command]
                       else
                         ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, node_command) }
                       end
          # Resolve symlinks to detect upgrades of Node.js installed via symlinks (e.g. Homebrew)
          path = candidates.find { File.file?(_1) && File.executable?(_1) }
          path && File.realpath(path)
        end

        def project_root #: String
          ::RuboCop::ConfigFinder.project_root || Dir.pwd
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
