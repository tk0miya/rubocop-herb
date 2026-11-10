# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

rubocop-herb is a RuboCop plugin gem for linting HTML + ERB files. It extracts Ruby code from ERB templates using the Herb parser and passes it to RuboCop for analysis.

## Goals

Use these goals to decide between trade-offs:

- Improve the accuracy of linting and formatting the Ruby parts of ERB templates
- Keep as many cops enabled as possible, unlike other implementations disabling many cops
  - Reduce false positives caused by the conversion from ERB (or the code rendered by rubocop-herb) as much as possible; the goal is zero
  - Report problems in the input ERB as much as possible (reduce false negatives)
- Autocorrection is optional. As AI lowers the cost of fixing offenses without autocorrection, never breaking templates and never misjudging take priority over the coverage of autocorrection

## Common Commands

```bash
# Setup
bin/setup                    # Install dependencies
npm ci                       # Install Node.js packages (herb-lint and herb-format, used by the tests of Herb/Linting and Herb/Formatting cops)

# Development
bin/rake                     # Run all checks (tests + linting)
bin/rake spec                # Run RSpec tests only
bin/rake rubocop             # Run RuboCop only
bin/rspec                    # Run RSpec tests directly
bin/console                  # Start IRB with gem loaded
bin/erb2ruby < file.erb      # Convert ERB to Ruby (dev tool)
```

### Development Tools

#### bin/erb2ruby

A development tool that reads ERB from stdin and outputs the converted Ruby code. Useful for debugging the Converter.

```bash
# Convert ERB from stdin
echo '<div><%= @name %></div>' | bin/erb2ruby
#=> div; _ = @name;  div;

# Convert ERB file
bin/erb2ruby < app/views/users/show.html.erb
```

#### Testing with RuboCop

Use `config/develop/rubocop.yml` to test rubocop-herb on ERB files:

```bash
# Run lint
echo '<%= "hello" %>' | bin/rubocop -c config/develop/rubocop.yml --stdin test.html.erb

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
4. **Extractor** returns the result to **RuboCop**
5. **RuboCop** analyzes the Ruby code; **RuboCopASTTransformer** renames the nodes rendered from HTML uniquely. RuboCop reports offenses at the positions in the original ERB source, as the Ruby code keeps the positions of the source

Data containers: `ParseResult` (holds parsed AST and metadata), `ProcessedSource` (RuboCop's source wrapper)

### Source Code Transformations

The converter converts the input file to Ruby code:

#### 1. Input File (HTML + ERB)

The original ERB template containing HTML markup and embedded Ruby code.

```erb
<div class="user">
  <%= @user.name %>
</div>
```

#### 2. Ruby Code

The input file parsed and converted to valid Ruby code. ERB tags are extracted as-is, and HTML tags are converted to Ruby-like identifiers (e.g., `<div>` → `div;`) to avoid false positives from cops like `Lint/EmptyBlock`. RuboCop parses this Ruby code to build an AST for analysis.

```ruby
div;
  _ = @user.name;
div;
```

### Positions and Newlines

The libraries count positions and newlines differently, so convert positions explicitly and never mix them:

| Library | Position | Unit | Newlines |
|---|---|---|---|
| Herb | `Herb::Range` (e.g. `token.range`) | Bytes | - |
| Herb | `Herb::Location` (e.g. `node.location`): line and column | Characters (codepoints) | `\n`, `\r\n` and a lone `\r` each start a new line |
| Parser / RuboCop | `Parser::Source::Range`, `begin_pos`, `column` | Characters | `Parser::Source::Buffer` normalizes `\r\n` to `\n`; a lone `\r` does not start a new line |
| rubocop-herb | `CharRange`, `ruby_code` | Characters | Line offsets in `Source` are computed with `String#each_line` (`\n` only) |

- Convert a `Herb::Range` with `Source#byte_to_char_pos` (or `NodeRange.byte_range_to_char_range`), and a `Herb::Location` with `Source#char_pos` (or `NodeRange.compute_char_range`)
- Test changes involving positions with multi-byte characters (e.g. Japanese text and emoji), as positions in bytes and characters only differ there
- The Extractor converts the source normalized by `Parser::Source::Buffer` (`\r\n` → `\n`) so that positions match RuboCop
- A lone `\r` is a newline for Herb but a space for Ruby and RuboCop, so `ErbParser` replaces it with a space before parsing with Herb to keep the lines of Herb locations in line with the source

### Key Components

Each class has a doc comment describing its details; read it before changing the class.
Paths are relative to `lib/rubocop/herb/` unless noted.

#### Conversion

- **Converter** (`converter.rb`): Orchestrates the conversion, produces `ruby_code`
- **ErbParser** (`erb_parser.rb`): Parses ERB with Herb and returns a `ParseResult` (`Source`, AST, ERB locations, disabled cops)
  - `erb_parser/node_location_collector.rb`, `erb_parser/disabled_cops_collector.rb`, `erb_parser/branches.rb`
- **RubyRenderer** (`ruby_renderer.rb`): Visitor rendering the Herb AST to Ruby code
- **Source** (`source.rb`), **NodeRange** (`node_range.rb`), **CharRange** (`char_range.rb`): Position conversion (see above)
- **ErbLocation**, **ErbNode**, **EscapedErbVisitor**, **RubyComment**: Helpers for ERB nodes, escaped tags (`<%%`) and ERB comments

#### RuboCop Integration

- **Plugin** / **Extractor**: Entry points registering the conversion with RuboCop
- **ProcessedSource** (`processed_source.rb`): Transforms the AST with **RuboCopASTTransformer** and builds the **CommentConfig** from `DisabledCopsCollector`, **ImmovableExpressionCollector** and **HtmlOnlyLineCollector**
- **CopOffenseFilter** + **VerbatimCode**: Suppress offenses on the code rendered by the conversion (`Configuration::VERBATIM_CODE_COPS`)
- **CopCorrectionGuard** + **CorrectionAdjuster** + **CorrectionValidator**: Trim and validate autocorrections so that they never break ERB tags
- **ReparsedEquivalenceAdapter**: Lets the cops reparsing their corrections compare with the AST before the transformation
- **Configuration** (`configuration.rb`): Extensions, `EXCLUDED_COPS`, `VERBATIM_CODE_COPS`, `UNCORRECTABLE_COPS`

#### Herb Tools Integration (herb-lint and herb-format)

- **Herb/Linting**, **Herb/Formatting** (`lib/rubocop/cop/herb/`): Run herb-lint / herb-format and report their results; shared logic in **HerbToolCop**
- **NodeServerClient** → **HerbLintClient**, **HerbFormatClient**: Clients of long-running Node.js servers
- `node_server.cjs`, `herb_lint_server.cjs`, `herb_format_server.cjs`: The servers (JSON Lines over stdin/stdout)

#### Other Cops (`lib/rubocop/cop/herb/`)

- **Herb/EmptyErbTag**: Removes empty ERB tags, including the ones left by other cops' corrections
- **Herb/IgnoredCopDirective**: Reports rubocop directives in ERB comments ignored because code or HTML follows them

### Design Rules

- Autocorrections must never break ERB tags. Guard them generically with `CorrectionAdjuster` / `CorrectionValidator` (or `UNCORRECTABLE_COPS`) rather than special-casing cops elsewhere
- Where to suppress false positives:
  - Caused by the ERB structure (e.g. branches containing only HTML) → `DisabledCopsCollector`
  - On the code rendered by the conversion (HTML markers, delimiters, semicolons) → `VERBATIM_CODE_COPS` (`CopOffenseFilter`)
  - Inherently incompatible with ERB → `EXCLUDED_COPS`
- Never patch individual cops (e.g. prepending to `RuboCop::Cop::Layout::IndentationConsistency` to override its private methods): their internals change silently between RuboCop versions.
  Patch only the parts of RuboCop shared by the cops (e.g. `Cop::Base`, `Cop::ReparsedEquivalence`), as `CopOffenseFilter`, `CopCorrectionGuard` and `ReparsedEquivalenceAdapter` do.
  If a cop cannot be fixed with these generic mechanisms, keep it in `EXCLUDED_COPS` (or disable it with `DisabledCopsCollector`).
- Herb cops correct the ERB source directly, so `CopCorrectionGuard` does not check them
- `CorrectionAdjuster` only keeps corrections from breaking ERB tags; the layout (lines and whitespace) is left to `Herb/EmptyErbTag` and herb-lint
- Herb/Linting and Herb/Formatting must not spawn Node.js unless needed, and report a startup error once per process (not for every file)
- Herb/Linting, Herb/Formatting and their servers resolve `.herb.yml` from the project root upwards and treat its patterns, custom rules and rewriters as relative to its directory, as the Herb CLIs do (the Ruby side and the servers must agree)

### Dependencies

- herb is still pre-1.0 and its AST changes between minor versions, so only the latest minor version is supported.
  When bumping herb to a new minor version, raise the lower bound in the gemspec as well and drop code for older versions.
  Do not add an upper bound.

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

- **Converter spec** (`spec/rubocop/herb/converter_spec.rb`): Use when testing the extraction of `ruby_code` from ERB templates. Focus on verifying the conversion logic itself.
- **Integration spec** (`spec/integration/`): Use when testing RuboCop lint and autocorrect results, such as which cops are triggered, how offenses are reported or how they are corrected.
  - `spec/integration/rubocop_spec.rb` uses the "with the whole RuboCop" shared context (`spec/support/whole_rubocop.rb`)
  - Follow `expect_offense` with `expect_correction` or `expect_no_corrections` in every example, so that corrections breaking the ERB source are caught (`expect_no_offenses` needs neither, as nothing is corrected without offenses)
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
  :tags #: Hash[Integer, String]
)
```

### Generating RBS Files

**Never edit `.rbs` files in `sig/` directly**; they are generated from the inline annotations by the PostToolUse hook.
