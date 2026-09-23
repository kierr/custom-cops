# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kierr/custom-cops.

## Adding a new cop

1. Generate the cop file under the appropriate department directory in `lib/rubocop/cop/`.
2. Add the cop to `config/default.yml` with a description and `Enabled: true`.
3. Add the cop to the require list in `lib/rubocop/custom_cops/cops.rb`.
4. Add tests in `test/` mirroring the source path.
5. Run `bundle exec rake test` and `bundle exec rubocop` to verify.
6. Run `bundle exec rake readme:generate` — or just commit, and the
   pre-commit hook regenerates it. CI fails if the README tables are stale.

## Running tests

```bash
bundle install
bundle exec rake test
```

## Linting

```bash
bundle exec rubocop
```

## Releasing

1. Update the version in `lib/custom_cops/version.rb`.
2. Run `bundle exec rake release` to build, tag, and push to rubygems.org.
