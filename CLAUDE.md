# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

rubocop-herb is a RuboCop plugin gem for linting HTML + ERB files. It extracts Ruby code from ERB templates using the Herb parser and passes it to RuboCop for analysis.

## Setup for Claude Code on the Web

When using Claude Code on the web (claude.ai/code), the environment is automatically configured by the SessionStart hook (`.claude/hooks/setup.sh`). This initializes rbenv with Ruby 3.3.6 and installs dependencies.

## Common Commands

```bash
# Setup
bin/setup                    # Install dependencies

# Development
bundle exec rake             # Run all checks (tests + linting)
bundle exec rake spec        # Run RSpec tests only
bundle exec rake rubocop     # Run RuboCop only
bin/console                  # Start IRB with gem loaded
bin/erb2ruby < file.erb      # Convert ERB to Ruby (dev tool)

# Gem management
bundle exec rake install     # Install gem locally
bundle exec rake release     # Release to RubyGems
```

### Development Tools

#### bin/erb2ruby

A development tool that reads ERB from stdin and outputs the converted Ruby code. Useful for debugging the Converter.

```bash
# Convert ERB from stdin (with HTML visualization enabled by default)
echo '<div><%= @name %></div>' | bin/erb2ruby
#=> div;     @name;         p0;

# Convert ERB without HTML visualization
echo '<div><%= @name %></div>' | bin/erb2ruby --disable-html-visualization
#=>          @name;

# Convert ERB file
bin/erb2ruby < app/views/users/show.html.erb
```

## Architecture

### Processing Pipeline

```
ERB source
    ↓
Source (parsing + ERB position collection)
    ↓
RubyRenderer (AST visitor-based rendering)
    ↓
Converter (generates ruby_code, hybrid_code, tags)
    ↓
Extractor (RuboCop integration)
    ↓
ProcessedSource (with RuboCopASTTransformer)
    ↓
RuboCop analysis
    ↓
Diagnostics (with HTML tag restoration)
```

1. **Source** parses ERB using `Herb.parse()`, collects ERB node positions and line offsets
2. **RubyRenderer** traverses the Herb AST using visitor pattern, extracts Ruby code by "bleaching" (replacing HTML with spaces to maintain line/column positions)
3. **Converter** orchestrates the process and produces `ruby_code`, `hybrid_code` (for display), and `tags` mapping
4. **ProcessedSource** wraps RuboCop's ProcessedSource and uses **RuboCopASTTransformer** to restore HTML tag information in the AST
5. RuboCop analyzes the extracted Ruby code with proper position mapping

### Source Code Transformations

The converter produces three representations of the source code:

#### 1. Input File (HTML + ERB)

The original ERB template containing HTML markup and embedded Ruby code.

```erb
<div class="user">
  <%= @user.name %>
</div>
```

#### 2. Ruby Code

The input file parsed and converted to valid Ruby code. ERB tags are extracted as-is, and HTML tags are converted to Ruby-like identifiers (when `html_visualization` is enabled). RuboCop parses this Ruby code to build an AST for analysis.

```ruby
div           ;
  @user.name;
p0;
```

#### 3. Hybrid Code

The Ruby code with HTML parts written back as HTML tags. Used by RuboCop during linting and formatting to understand and display the original input file's content in diagnostics.

```
<div class="user">
  @user.name;
</div>
```

### Key Components

#### Core Processing

- **Source** (`lib/rubocop/herb/source.rb`): Parses ERB using `Herb.parse()`, collects ERB node positions and line offsets, provides utility methods for byte slicing and range conversion
- **RubyRenderer** (`lib/rubocop/herb/ruby_renderer.rb`): Visitor-based renderer that traverses Herb AST and renders Ruby code. Handles ERB blocks, control flow, comments, and HTML visualization
- **RubyRenderer::BlockContext** (`lib/rubocop/herb/ruby_renderer/block_context.rb`): Tracks block context for determining tail expressions in control flow
- **Converter** (`lib/rubocop/herb/converter.rb`): Orchestrates the conversion process, produces `ruby_code`, `hybrid_code`, and `tags` mapping
- **ErbNodePositionCollector** (`lib/rubocop/herb/erb_node_position_collector.rb`): Visitor that collects ERB node positions for determining if HTML elements contain ERB

#### RuboCop Integration

- **Plugin** (`lib/rubocop/herb/plugin.rb`): LintRoller plugin entry point, registers the Extractor with RuboCop
- **Extractor** (`lib/rubocop/herb/extractor.rb`): RuboCop extractor interface that converts ERB files to Ruby for analysis
- **ProcessedSource** (`lib/rubocop/herb/processed_source.rb`): RuboCop ProcessedSource subclass that stores hybrid_code and tags, transforms AST after parsing
- **RuboCopASTTransformer** (`lib/rubocop/herb/rubocop_ast_transformer.rb`): AST processor that restores original HTML tag information in parsed AST nodes
- **Configuration** (`lib/rubocop/herb/configuration.rb`): Manages supported extensions, excluded cops, and html_visualization setting
- **patch/team.rb** (`lib/rubocop/herb/patch/team.rb`): Monkey patch for RuboCop Team class to fix autocorrect with ruby_extractors

#### Utilities

- **Characters** (`lib/rubocop/herb/characters.rb`): Byte constants for character manipulation (LF, CR, SPACE, HASH, SEMICOLON, etc.)
- **Tag** (`lib/rubocop/herb/tag.rb`): Data class storing tag range information for AST restoration

### Dependencies

- `herb` (>= 0.8.0): ERB parser that provides AST for HTML+ERB files
- `lint_roller` (>= 1.1.0): RuboCop plugin framework for registering extractors

### Configuration Options

The plugin supports these configuration options in `.rubocop.yml`:

```yaml
rubocop-herb:
  extensions:
    - .html.erb           # Default: [".html.erb"]
  html_visualization: true # Default: false - renders HTML tags as Ruby identifiers
```

**HTML Visualization**: When enabled, HTML tags are rendered as Ruby identifiers (e.g., `<div>` → `div;`) to avoid false positives from cops like `Lint/EmptyBlock`. The original HTML is restored in diagnostics via AST transformation.

## Code Conventions

- All methods use RBS inline annotations (`@rbs` comments)
- Type signatures are generated in `sig/` directory
- Double-quoted strings preferred
- Frozen string literals required

### Testing Conventions

- In integration specs, always use `eq` instead of `include` when comparing offenses
  - Using `include` hides other unexpected offenses, making debugging difficult
  - Example: `expect(offenses).to eq []` instead of `expect(offenses).not_to include("Lint/Void")`
  - The example title should describe the purpose (e.g., "does not trigger Lint/Void"), but the assertion should use `eq` to catch all offenses

### Writing Type Annotations

This project uses [rbs-inline](https://github.com/soutaro/rbs-inline) style annotations. Types are written as comments in Ruby source files:

- **Argument types**: Use `@rbs argname: Type` comments before the method
- **Return types**: Use `#: Type` comment at the end of the `def` line
- **Attributes**: Use `#: Type` comment at the end of `attr_accessor`/`attr_reader` (also defines instance variable type)
- **Instance variables**: Use `@rbs @name: Type` comment (must have blank line before method definition)
- **Data classes**: Use `#: Type` comment at the end of each member in `Data.define`

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

# Data class with typed members
Result = Data.define(
  :source, #: Source
  :code, #: String
  :tags #: Hash[Integer, Tag]
)
```

### Generating RBS Files

Type definition files (`.rbs`) are generated automatically by the PostToolUse hook when `.rb` files in `lib/` are modified. **Never edit `.rbs` files directly** - always modify the inline annotations in Ruby source files.
