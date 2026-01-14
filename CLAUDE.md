# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

rubocop-herb is a RuboCop plugin gem for linting HTML + ERB files. It extracts Ruby code from ERB templates using the Herb parser and passes it to RuboCop for analysis.

## Common Commands

```bash
# Setup
bin/setup                    # Install dependencies

# Development
bundle exec rake             # Run all checks (tests + linting)
bundle exec rake spec        # Run RSpec tests only
bundle exec rake rubocop     # Run RuboCop only
bin/console                  # Start IRB with gem loaded

# Gem management
bundle exec rake install     # Install gem locally
bundle exec rake release     # Release to RubyGems
```

## Architecture

### Processing Pipeline

```
ERB source → Converter → Bleached Ruby code → RuboCop → Diagnostics
```

1. **Converter** parses ERB using `Herb.parse()`, extracts Ruby code, and preserves byte offsets
2. The "bleaching" process replaces HTML with spaces to maintain line/column positions
3. RuboCop analyzes the extracted Ruby code
4. Diagnostics can be mapped back to original ERB positions via byte offsets

### Key Components

- **Plugin** (`lib/rubocop/herb/plugin.rb`): LintRoller plugin entry point, registers the Extractor with RuboCop
- **Converter** (`lib/rubocop/herb/converter.rb`): Core logic - converts ERB to extractable Ruby while preserving byte lengths
- **ErbNodeCollector** (`lib/rubocop/herb/erb_node_collector.rb`): Visitor pattern implementation that traverses Herb AST to collect ERB nodes
- **Extractor** (`lib/rubocop/herb/extractor.rb`): RuboCop extractor interface (skeleton)

### Dependencies

- `herb` (>= 0.8.0): ERB parser
- `lint_roller` (>= 1.1.0): RuboCop plugin framework

## Code Conventions

- All methods use RBS inline annotations (`@rbs` comments)
- Type signatures are generated in `sig/` directory
- Double-quoted strings preferred
- Frozen string literals required

### Writing Type Annotations

This project uses [rbs-inline](https://github.com/soutaro/rbs-inline) style annotations. Types are written as comments in Ruby source files:

- **Argument types**: Use `@rbs argname: Type` comments before the method
- **Return types**: Use `#: Type` comment at the end of the `def` line
- **Attributes**: Use `#: Type` comment at the end of `attr_accessor`/`attr_reader` (also defines instance variable type)
- **Instance variables**: Use `@rbs @name: Type` comment (must have blank line before method definition)

```ruby
# @rbs name: String
# @rbs age: Integer
def greet(name, age) #: String
  "Hello, #{name}! You are #{age} years old."
end

attr_reader :name #: String

# @rbs @count: Integer

def initialize
  @count = 0
end
```

### Generating RBS Files

Type definition files (`.rbs`) are generated from inline annotations using `rbs-inline`. **Never edit `.rbs` files directly** - always modify the inline annotations in Ruby source files and regenerate:

```bash
# Generate RBS for a specific file
bundle exec rbs-inline --opt-out --output=sig/ [filename]

# Generate RBS for all files
bundle exec rbs-inline --opt-out --output=sig/ lib/
```

After modifying type annotations, always regenerate the RBS files and run type checking:

```bash
bundle exec rbs-inline --opt-out --output=sig/ lib/
bundle exec steep check
```
