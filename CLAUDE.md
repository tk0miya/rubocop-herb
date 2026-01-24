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
bin/rake                     # Run all checks (tests + linting)
bin/rake spec                # Run RSpec tests only
bin/rake rubocop             # Run RuboCop only
bin/rspec                    # Run RSpec tests directly
bin/console                  # Start IRB with gem loaded
bin/erb2ruby < file.erb      # Convert ERB to Ruby (dev tool)

# Gem management
bin/rake install             # Install gem locally
bin/rake release             # Release to RubyGems
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

#### Testing with RuboCop

Use `config/develop/rubocop.yml` to test rubocop-herb on ERB files:

```bash
# Run lint
echo '<%= "hello" %>' | bin/rubocop -c config/develop/rubocop.yml --stdin test.html.erb

# Run lint with HTML visualization enabled
echo '<%= "hello" %>' | bin/rubocop -c config/develop/rubocop-html-visualization.yml --stdin test.html.erb

# Run autocorrect
echo '<%= "hello" %>' | bin/rubocop -c config/develop/rubocop.yml -a --stdin test.html.erb

# Run specific cops only
echo '<%= "hello" %>' | bin/rubocop -c config/develop/rubocop.yml --only Style/StringLiterals --stdin test.html.erb
```

## Architecture

### Processing Pipeline

```
RuboCop ─── calls ───→ Extractor
                           ↓
                       Converter
                           ↓
                       ErbParser
                           ↓
                       RubyRenderer
                           ↓
RuboCop ←── returns ─── Extractor
```

1. **RuboCop** invokes the **Extractor** for `.html.erb` files
2. **Extractor** calls **Converter** to convert ERB source to Ruby code
3. **Converter** orchestrates the conversion:
   - Calls **ErbParser** to parse ERB and produce a `ParseResult` (data class holding AST, ERB locations, and metadata)
   - Calls **RubyRenderer** to traverse the AST and render Ruby code
   - Generates `ruby_code`, `hybrid_code` (for display), and `tags` mapping
4. **Extractor** returns the result to **RuboCop**
5. **RuboCop** analyzes the Ruby code; **RuboCopASTTransformer** restores HTML tag information in diagnostics

Data containers: `ParseResult` (holds parsed AST and metadata), `ProcessedSource` (RuboCop's source wrapper)

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

- **ErbParser** (`lib/rubocop/herb/erb_parser.rb`): Responsible for parsing and analyzing ERB documents. Parses using `Herb.parse()`, collects node locations via `NodeLocationCollector`, collects tail expressions via `TailExpressionCollector`, and creates a `Source` object. Returns a `ParseResult`
- **ParseResult** (`lib/rubocop/herb/parse_result.rb`): Data class holding parsed AST, ERB locations, line offsets, and utility methods for byte slicing and range conversion
- **RubyRenderer** (`lib/rubocop/herb/ruby_renderer.rb`): Responsible for converting parsed results to Ruby code. Visitor-based renderer that traverses Herb AST and renders Ruby code. Handles ERB blocks, control flow, comments, and HTML visualization
- **Converter** (`lib/rubocop/herb/converter.rb`): Orchestrates the conversion process, produces `ruby_code`, `hybrid_code`, and `tags` mapping
- **NodeLocationCollector** (`lib/rubocop/herb/erb_parser/node_location_collector.rb`): Visitor that collects ERB and HTML node locations for determining element positions
- **TailExpressionCollector** (`lib/rubocop/herb/erb_parser/tail_expression_collector.rb`): Collects tail expression positions for control flow handling
- **Source** (`lib/rubocop/herb/source.rb`): Encapsulates source code and line offset information for byte/position calculations
- **NodeRange** (`lib/rubocop/herb/node_range.rb`): Data class storing node range information (start/end positions)

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
plugins:
  - rubocop-herb:
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

#### Assertion Guidelines

- **Always use exact match assertions**: Use `eq` or `be` for comparisons instead of partial matchers like `include` or negations like `not_to`
  - Partial matches can hide unexpected errors or extra values in the result
  - Example: `expect(result).to eq ["expected"]` instead of `expect(result).to include("expected")`
  - Example: `expect(offenses).to eq []` instead of `expect(offenses).not_to include("SomeCop")`
- The example title should describe the intent (e.g., "does not trigger Lint/Void"), but the assertion itself should use exact matching to catch all discrepancies

#### Choosing Between Integration Spec and Converter Spec

- **Converter spec** (`spec/rubocop/herb/converter_spec.rb`): Use when testing the extraction of `ruby_code` and `hybrid_code` from ERB templates. Focus on verifying the conversion logic itself.
- **Integration spec** (`spec/integration/`): Use when testing RuboCop lint results, such as which cops are triggered or how offenses are reported.
- **When in doubt, use Converter spec**: If you're unsure which to use, write tests in the Converter spec. It's better to test the conversion logic directly.

### Writing Type Annotations

This project uses [rbs-inline](https://github.com/soutaro/rbs-inline) style annotations. Types are written as comments in Ruby source files:

- **Argument types**: Use `@rbs argname: Type` comments before the method. Add `-- description` for documentation (e.g., `@rbs column: Integer -- 0-based column number`)
- **Return types**: Use `#: Type` comment at the end of the `def` line
- **Attributes**: Use `#: Type` comment at the end of `attr_accessor`/`attr_reader` (also defines instance variable type)
- **Instance variables**: Use `@rbs @name: Type` comment (must have blank line before method definition)
- **Data classes**: Use `#: Type` comment at the end of each member in `Data.define`

```ruby
# @rbs name: String -- the user's name
# @rbs age: Integer -- the user's age in years
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
  :parse_result, #: ParseResult
  :code, #: String
  :tags #: Hash[Integer, Tag]
)
```

### Generating RBS Files

Type definition files (`.rbs`) are generated automatically by the PostToolUse hook when `.rb` files in `lib/` are modified. **Never edit `.rbs` files directly** - always modify the inline annotations in Ruby source files.
