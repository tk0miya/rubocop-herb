# frozen_string_literal: true

module RuboCop
  module Herb
    # Client of the herb-format server (herb_format_server.cjs).
    class HerbFormatClient < NodeServerClient
      # The script of the herb-format server
      SERVER_SCRIPT = File.expand_path("herb_format_server.cjs", __dir__.not_nil!) #: String

      # @rbs override
      def self.server_scripts
        [*super, SERVER_SCRIPT]
      end

      # Returns the fixes turning the source into the one formatted by herb-format,
      # one for each changed part of the lines (empty if the source is formatted,
      # or herb-format does not format the file).
      # Raises StartupError if the server fails to start.
      # @rbs path: String -- absolute path of the file
      # @rbs source: String -- content of the file
      def format(path, source) #: Array[NodeServerClient::Fix]
        response = request({ path:, source: })
        response.fetch("fixes").map { build_fix(_1).not_nil! }
      end

      private

      # @rbs override
      def tool_name
        "herb-format"
      end

      # @rbs override
      def server_script
        SERVER_SCRIPT
      end
    end
  end
end
