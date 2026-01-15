#!/bin/bash

# Initialize rbenv and set Ruby version for Claude Code on the Web
eval "$(rbenv init -)"
rbenv local 3.3.6

# Install dependencies
# Note: Bundler 4.0.3 has a bug with Ruby 3.3.x causing CGI class variable errors.
# Install and use Bundler 2.x to avoid this issue.
gem install bundler -v 2.7.2 --no-document
bundle _2.7.2_ install

# Persist environment for subsequent commands
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'eval "$(rbenv init -)"' >> "$CLAUDE_ENV_FILE"
fi

exit 0
