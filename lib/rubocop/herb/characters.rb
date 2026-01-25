# frozen_string_literal: true

module RuboCop
  module Herb
    # Byte and string constants for character manipulation
    module Characters
      LF = 0x0A #: Integer
      CR = 0x0D #: Integer
      SPACE = 0x20 #: Integer
      HASH = 0x23 #: Integer
      SEMICOLON = 0x3B #: Integer
      EQUALS = 0x3D #: Integer
      UNDERSCORE = 0x5F #: Integer
      DIGIT_ZERO = 0x30 #: Integer
      LOWERCASE_A = 0x61 #: Integer
      LEFT_BRACE = 0x7B #: Integer
      RIGHT_BRACE = 0x7D #: Integer

      # String constants for character-based buffer operations
      CHAR_LF = "\n" #: String
      CHAR_CR = "\r" #: String
      CHAR_SPACE = " " #: String
      CHAR_HASH = "#" #: String
      CHAR_SEMICOLON = ";" #: String
      CHAR_EQUALS = "=" #: String
      CHAR_UNDERSCORE = "_" #: String
      CHAR_LEFT_BRACE = "{" #: String
      CHAR_RIGHT_BRACE = "}" #: String
    end
  end
end
