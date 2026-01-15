#!/bin/bash

# Initialize rbenv and set Ruby version for Claude Code on the Web
eval "$(rbenv init -)"
rbenv local 3.3.6

# Install dependencies
bundle install

# Persist environment for subsequent commands
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'eval "$(rbenv init -)"' >> "$CLAUDE_ENV_FILE"
fi

exit 0
