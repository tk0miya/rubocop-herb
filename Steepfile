# frozen_string_literal: true

# D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"
  # herb's RBS uses SimpleDelegator without declaring the `delegate` stdlib
  # dependency. Steep 2.0 enforces this strictly. Loading the library on
  # our side works around the issue. Skipped on Steep 1.x because doing so
  # there causes unrelated cascading type errors.
  library "delegate" if Gem::Version.new(Steep::VERSION) >= Gem::Version.new("2.0.0")
  implicitly_returns_nil!
end
