#!/bin/bash

# Initialize rbenv and set Ruby version for Claude Code on the Web
eval "$(rbenv init -)"
rbenv local 3.3.6

# Install dependencies
# Note: Bundler 4.0.3 has a bug with Ruby 3.3.x causing CGI class variable errors.
# Use Bundler 2.5.22 to avoid this issue.
bundle _2.5.22_ install

# Persist environment for subsequent commands
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'eval "$(rbenv init -)"' >> "$CLAUDE_ENV_FILE"
fi

exit 0
