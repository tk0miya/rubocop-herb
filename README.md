# Rubocop::Herb

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/rubocop/herb`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

Add rubocop-herb to the plugins in `.rubocop.yml`:

```yaml
plugins:
  - rubocop-herb
```

### Autocorrection

`rubocop -a` / `rubocop -A` correct the Ruby code in ERB tags. HTML is kept as is,
though whitespace around ERB tags (indentation and newlines) may change.

A correction that cannot keep the HTML (e.g. swapping `if`/`else` branches containing HTML,
or removing blank lines between HTML tags) is not applied. Such offenses are reported as not autocorrectable.

### Line length

`Layout/LineLength` checks only the lines with ERB tags.
Lines without ERB tags are HTML only, whose length is left to
[herb-format](https://herb-tools.dev/projects/formatter) as it wraps HTML (e.g. attributes) by itself.
herb-format does not wrap the Ruby code in ERB tags, so RuboCop still checks the lines with ERB tags.

### Running herb-lint together (Herb/Linting cop)

The `Herb/Linting` cop (enabled by default) runs [herb-lint](https://herb-tools.dev/projects/linter)
on HTML+ERB files and reports its offenses together with RuboCop's ones.
It requires Node.js and `@herb-tools/linter` installed in the project:

```bash
npm install --save-dev @herb-tools/linter
```

If herb-lint is not available, the cop reports an error asking to set it up
(reported once, not for every file).
To use rubocop-herb without herb-lint, disable the cop in `.rubocop.yml`:

```yaml
Herb/Linting:
  Enabled: false
  # NodeCommand: node  # The Node.js executable (default: node)
```

herb-lint is configured with `.herb.yml` in the project root as usual
(rules, `linter.exclude`, custom rules in `.herb/rules/`, and `<%# herb:disable %>` comments work as in herb-lint).
`<%# rubocop:disable Herb/Linting %>` also disables the cop.

Offenses are reported as `[rule-name] message`, and the severities of herb-lint are mapped to
RuboCop's ones as follows: `error` → `error`, `warning` → `warning`, `info` → `convention`, `hint` → `refactor`.

A Node.js process is spawned once per RuboCop process and reused for all files,
so the startup cost of Node.js (a few hundred milliseconds) is paid only once.
With `rubocop --parallel`, each worker process spawns its own one.

Limitations:

- Autocorrection of herb-lint is not supported. Run `herb-lint --fix` instead.
- The `erb-no-empty-tags` rule is not reported, as the `Herb/EmptyErbTag` cop reports and autocorrects it.
- herb-lint does not run on files where the Ruby code has syntax errors.
- Rules that analyze other templates (e.g. partials and their callers) run without the project-wide analysis,
  so that RuboCop's result cache stays valid per file.

### Herb/IgnoredCopDirective cop

rubocop-herb converts an ERB comment to a Ruby comment so that RuboCop processes it
(including `<%# rubocop:disable %>` directives).
But rubocop-herb cannot convert an ERB comment followed by ERB tags or HTML on the same line,
because the Ruby comment would comment out the following code; rubocop-herb ignores such a comment.
This is harmless for ordinary comments, but rubocop directives in such a comment have no effect.
The `Herb/IgnoredCopDirective` cop (enabled by default) reports rubocop directives
ignored by rubocop-herb because ERB tags or HTML follow them on the same line:

```erb
<%# bad: rubocop-herb ignores this directive %>
<%# rubocop:disable Lint/Void %><%= user.name %>

<%# good %>
<%# rubocop:disable Lint/Void %>
<%= user.name %>
```

To disable the cop, configure it in `.rubocop.yml`:

```yaml
Herb/IgnoredCopDirective:
  Enabled: false
```

It does not support autocorrection, because inserting a line break may change the rendered whitespace
and the indentation of the following code depends on the surrounding HTML.

### Herb/CommentedOutCode cop

ERB compiles a template into Ruby code keeping its lines, so a Ruby comment at the end of the code
in an ERB tag (e.g. `<% x # comment %>`) comments out the ERB tags and HTML following it on the same line.
The template outputs nothing for them, or fails with a syntax error (e.g. when `<% end %>` is commented out).
rubocop-herb renders such a comment as is, as ERB does, so RuboCop does not check the code commented out.
The `Herb/CommentedOutCode` cop (enabled by default) reports such comments:

```erb
<%# bad: the comment comments out `<%= name %>` %>
<% name = user.name # the full name %><%= name %>

<%# good %>
<% name = user.name # the full name %>
<%= name %>

<%# good %>
<% name = user.name %><%# the full name %><%= name %>
```

To disable the cop, configure it in `.rubocop.yml`:

```yaml
Herb/CommentedOutCode:
  Enabled: false
```

It does not support autocorrection, because inserting a line break may change the rendered whitespace.

### Herb/EmptyErbTag cop

The `Herb/EmptyErbTag` cop (enabled by default) reports empty ERB tags (`<% %>`) and empty ERB comments (`<%# %>`),
which output nothing, and removes them by autocorrection:

```erb
<%# bad %>
<p>a</p>
<% %>
<p>b</p>

<%# good %>
<p>a</p>
<p>b</p>
```

An autocorrection removing the whole code of an ERB tag (e.g. `Lint/Void` removing `1` from `<% 1 %>`)
keeps the delimiters of the tag, so that it does not break the template.
This cop removes the empty tag left by it, as the statement is removed in Ruby files.
The line of the tag is removed if it has only empty tags.
The whitespace before the tag is removed if the tag ends the line, so as not to leave trailing whitespace.
The whitespace trimmed by the trim markers (`<%-` and `-%>`) is removed along with the tag.

The cop replaces the `erb-no-empty-tags` rule of herb-lint, so `Herb/Linting` does not report the rule.

To disable the cop, configure it in `.rubocop.yml`:

```yaml
Herb/EmptyErbTag:
  Enabled: false
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/rubocop-herb. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/rubocop-herb/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rubocop::Herb project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/rubocop-herb/blob/main/CODE_OF_CONDUCT.md).
