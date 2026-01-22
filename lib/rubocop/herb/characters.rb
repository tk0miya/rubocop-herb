# frozen_string_literal: true

module RuboCop
  module Herb
    # Byte constants for character manipulation
    module Characters
      LF = 0x0A #: Integer
      CR = 0x0D #: Integer
      SPACE = 0x20 #: Integer
      HASH = 0x23 #: Integer
      SEMICOLON = 0x3B #: Integer
      EQUALS = 0x3D #: Integer
      UNDERSCORE = 0x5F #: Integer
      DIGIT_ZERO = 0x30 #: Integer
      LEFT_BRACE = 0x7B #: Integer
      RIGHT_BRACE = 0x7D #: Integer
    end
  end
end
