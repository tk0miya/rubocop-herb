# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

rubocop-herb is a RuboCop plugin gem for linting HTML + ERB files. It extracts Ruby code from ERB templates using the Herb parser and passes it to RuboCop for analysis.

## Setup for Claude Code on the Web

When using Claude Code on the web (claude.ai/code), the environment is automatically configured by the SessionStart hook (`.claude/hooks/claude-code-web-session-start.sh`). This initializes rbenv, installs dependencies, installs the RBS collection and installs Node.js packages.

## Common Commands

```bash
# Setup
bin/setup                    # Install dependencies
npm ci                       # Install Node.js packages (herb-lint, used by the tests of Herb/Linting cop)

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
#=> div; _ = @name;  div;

# Convert ERB without HTML visualization
echo '<div><%= @name %></div>' | bin/erb2ruby --disable-html-visualization
#=>      _ = @name;

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
div {
  _ = @user.name;
};
```

#### 3. Hybrid Code

The Ruby code with HTML parts written back as HTML tags. Used by RuboCop during linting and formatting to understand and display the original input file's content in diagnostics.

```
<div class="user">
  _ = @user.name;
</div>
```

### Key Components

#### Core Processing

- **ErbParser** (`lib/rubocop/herb/erb_parser.rb`): Responsible for parsing and analyzing ERB documents. Parses using `Herb.parse()`, collects node locations via `NodeLocationCollector`, collects lines to disable cops via `DisabledCopsCollector`, and creates a `Source` object. Returns a `ParseResult`
- **ParseResult** (`lib/rubocop/herb/parse_result.rb`): Data class holding the `Source`, parsed AST, ERB locations, tags and disabled cops, plus utility methods for slicing and lookups
- **RubyRenderer** (`lib/rubocop/herb/ruby_renderer.rb`): Responsible for converting parsed results to Ruby code. Visitor-based renderer that traverses Herb AST and renders Ruby code. Handles ERB blocks, control flow, comments, and HTML visualization
- **Converter** (`lib/rubocop/herb/converter.rb`): Orchestrates the conversion process, produces `ruby_code`, `hybrid_code`, and `tags` mapping
- **NodeLocationCollector** (`lib/rubocop/herb/erb_parser/node_location_collector.rb`): Visitor that collects ERB and HTML node locations for determining element positions
- **DisabledCopsCollector** (`lib/rubocop/herb/erb_parser/disabled_cops_collector.rb`): Collects the lines where cops should be disabled to avoid false positives caused by the conversion (e.g., conditional branches containing only HTML, or HTML elements rendered as `tag { ... }`)
- **Source** (`lib/rubocop/herb/source.rb`): Encapsulates source code and line offset information for byte/position calculations
- **NodeRange** (`lib/rubocop/herb/node_range.rb`): Utility module that computes the character range (`CharRange`) of a Herb AST node

#### RuboCop Integration

- **Plugin** (`lib/rubocop/herb/plugin.rb`): LintRoller plugin entry point, registers the Extractor with RuboCop
- **Extractor** (`lib/rubocop/herb/extractor.rb`): RuboCop extractor interface that converts ERB files to Ruby for analysis
- **ProcessedSource** (`lib/rubocop/herb/processed_source.rb`): RuboCop ProcessedSource subclass that stores hybrid_code and tags, transforms AST after parsing, and provides a CommentConfig built from `ParseResult#disabled_cops`, `ImmovableExpressionCollector`, `IndentationConsistencyCollector` and `CommentIndentationCollector`
- **CommentConfig** (`lib/rubocop/herb/comment_config.rb`): RuboCop CommentConfig subclass that disables cops at given line ranges as if `rubocop:disable` comments were written there
- **ImmovableExpressionCollector** (`lib/rubocop/herb/immovable_expression_collector.rb`): Collects the lines to disable `Style/IdenticalConditionalBranches` for expressions that cannot be moved out of conditionals because HTML is next to them (e.g., `<div><%= x %></div>` in every branch). Works on the Ruby AST, so it applies regardless of `html_visualization`
- **IndentationConsistencyCollector** (`lib/rubocop/herb/indentation_consistency_collector.rb`): Collects the lines to disable `Layout/IndentationConsistency` for statements not in the same ERB tag as the first statement of their body, because they are indented by the HTML structure (e.g., `<% a = 1 %>` followed by `<p><% b = 2 %></p>`). Works on the Ruby AST and the ERB tag ranges
- **CommentIndentationCollector** (`lib/rubocop/herb/comment_indentation_collector.rb`): Collects the lines to disable `Layout/CommentIndentation` for comments not in the same ERB tag as the code on the next non-blank line, because they are indented by the HTML structure (e.g., `<%# note %>` followed by `<%= x %>`). Works on the comments and the ERB tag ranges
- **RuboCopASTTransformer** (`lib/rubocop/herb/rubocop_ast_transformer.rb`): AST processor that restores original HTML tag information in parsed AST nodes, and renames nodes rendered from HTML uniquely so that cops comparing code (e.g. `Lint/DuplicateBranch`) only compare the Ruby parts
- **Configuration** (`lib/rubocop/herb/configuration.rb`): Manages supported extensions, excluded cops, html_visualization setting, and the default configuration of `Herb/Linting` cop

#### herb-lint Integration

- **Herb/Linting cop** (`lib/rubocop/cop/herb/linting.rb`): Runs herb-lint (`@herb-tools/linter`, a Node.js package) on HTML+ERB files and reports its offenses as RuboCop offenses. Enabled by default; if herb-lint is not available, it reports an error once (not for every file) to ask users to set it up or disable the cop. Its name, message format (`[rule] message`) and severity mapping are aligned with the `Herb/Linting` cop of the upstream prototype (`rubocop-herb` branch of marcoroth/herb) for compatibility
- **HerbLintClient** (`lib/rubocop/herb/herb_lint_client.rb`): Spawns the herb-lint server once per process (lazily, so that forked workers of `rubocop --parallel` spawn their own one) and sends files to it
- **herb-lint server** (`lib/rubocop/herb/herb_lint_server.cjs`): Node.js script that loads herb-lint from the project and lints files received over stdin (JSON Lines protocol)

#### Utilities

- **CharRange** (`lib/rubocop/herb/char_range.rb`): Data class storing a character-based (not byte-based) range
- **ErbLocation** (`lib/rubocop/herb/erb_location.rb`): Location and metadata (type, node, range, line, column) of an ERB node
- **Tag** (`lib/rubocop/herb/tag.rb`): Data class storing tag range information for AST restoration

### Dependencies

- `herb` (>= 0.11.0): ERB parser that provides AST for HTML+ERB files
  - herb is still pre-1.0 and its AST changes between minor versions, so only the latest minor version is supported.
    When bumping herb to a new minor version, raise the lower bound in the gemspec as well and drop code for older versions.
    Do not add an upper bound.
- `lint_roller` (>= 1.1.0): RuboCop plugin framework for registering extractors
- `not_nilable`: Provides `#not_nil!` for unwrapping nilable values with type narrowing
- `rubocop` (>= 1.90.0): The linter itself; 1.90.0 is required because `CommentConfig` overrides `cop_enabled_at_lines?`, introduced in that version

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
