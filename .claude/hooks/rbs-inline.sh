#!/bin/bash

# Hook input is JSON from stdin
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

# Only run for Edit or Write tools on .rb files in lib/
if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
    exit 0
fi

if [[ ! "$file_path" =~ \.rb$ ]]; then
    exit 0
fi

if [[ ! "$file_path" =~ /lib/ ]]; then
    exit 0
fi

cd "$CLAUDE_PROJECT_DIR" || exit 1

# Initialize rbenv with Ruby 3.3.6
eval "$(rbenv init -)" 2>/dev/null || true
export RBENV_VERSION=3.3.6

echo "Running rbs-inline for $file_path..." >&2

# Generate RBS for the modified file
if ! bundle exec rbs-inline --opt-out --output=sig/ "$file_path" >&2; then
    echo "Warning: RBS generation failed for $file_path" >&2
    # Don't block the operation, just warn
    exit 0
fi

echo "RBS generation completed." >&2
exit 0
