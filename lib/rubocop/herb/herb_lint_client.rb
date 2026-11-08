# frozen_string_literal: true

module RuboCop
  module Herb
    # Client of the herb-lint server (herb_lint_server.cjs).
    class HerbLintClient < NodeServerClient
      # An offense reported by herb-lint.
      # Lines are 1-based and columns are 0-based character offsets.
      # The fix is nil if the offense is not autocorrectable.
      Offense = Data.define(
        :rule,          #: String
        :message,       #: String
        :severity,      #: String
        :start_line,    #: Integer
        :start_column,  #: Integer
        :end_line,      #: Integer
        :end_column,    #: Integer
        :fix            #: NodeServerClient::Fix?
      )

      # The script of the herb-lint server
      SERVER_SCRIPT = File.expand_path("herb_lint_server.cjs", __dir__.not_nil!) #: String

      # @rbs override
      def self.server_scripts
        [*super, SERVER_SCRIPT]
      end

      # Raises StartupError if the server fails to start.
      # @rbs path: String -- absolute path of the file
      # @rbs source: String -- content of the file
      # @rbs unsafe_fixes: bool -- whether to include the unsafe fixes (`herb-lint --fix-unsafely`) in the offenses
      def lint(path, source, unsafe_fixes: false) #: Array[Offense]
        response = request({ path:, source:, unsafeFixes: unsafe_fixes })
        response.fetch("offenses").map { build_offense(_1) }
      end

      private

      # @rbs override
      def tool_name
        "herb-lint"
      end

      # @rbs override
      def server_script
        SERVER_SCRIPT
      end

      # @rbs offense: Hash[String, untyped]
      def build_offense(offense) #: Offense
        location = offense.fetch("location")
        Offense.new(
          rule: offense.fetch("rule"),
          message: offense.fetch("message"),
          severity: offense.fetch("severity"),
          start_line: location.dig("start", "line"),
          start_column: location.dig("start", "column"),
          end_line: location.dig("end", "line"),
          end_column: location.dig("end", "column"),
          fix: build_fix(offense["fix"])
        )
      end
    end
  end
end
