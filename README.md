# custom-cops

A RuboCop extension with 135 cops covering lint, Rails, Sorbet, security, Karafka,
migration safety, logging, test structure, Zeitwerk, and more. Abstracted from a
large Rails monolith, distilling over a decade of production wisdom and insight.

Very much bespoke, published so others can cherry pick or learn from these patterns.

## Contents

- [Installation](#installation)
- [Usage](#usage)
- [Departments](#departments)
- [Cops by Department](#cops-by-department)
- [Requirements](#requirements)
- [License](#license)

## Installation

Add to your Gemfile:

```ruby
gem 'custom-cops', require: false
```

Or install locally:

```bash
gem install custom-cops
```

## Usage

Add to your `.rubocop.yml`:

```yaml
require:
  - custom-cops
```

All cops are enabled by default. Disable individually:

```yaml
Lint/DeadExpressionBetweenSigAndDef:
  Enabled: false
```

### Configurable cops

Some cops accept configuration in `.rubocop.yml`:

```yaml
Zeitwerk/NamespaceTableName:
  Namespaces:
    - Source

Rails/AfterCreateInsteadOfAfterCommit:
  ExternalReceiverPatterns:
    - KafkaProducer
    - GraphClient

Lint/HardcodedUuidInSource:
  Exclude:
    - db/**/*
```

## Departments

<!-- departments:start -->
| Department | Cops | Focus |
|---|---|---|
| [Lint](#lint) | 68 | Code-quality and correctness |
| [Rails](#rails) | 13 | Rails conventions and safety |
| [Logging](#logging) | 10 | Structured logging conventions |
| [Sorbet](#sorbet) | 10 | Type-system consistency |
| [MigrationSafety](#migrationsafety) | 6 | Safe Postgres migrations |
| [Test](#test) | 6 | Test structure and conventions |
| [Karafka](#karafka) | 5 | Consumer and producer safety |
| [Security](#security) | 5 | Security anti-patterns |
| [Style](#style) | 5 | Code style and readability |
| [Zeitwerk](#zeitwerk) | 3 | Autoloading consistency |
| [Performance](#performance) | 1 | Performance anti-patterns |
| [Secrets](#secrets) | 1 | Secret/credential handling |
| [Service](#service) | 1 | Service object conventions |
| [Time](#time) | 1 | Time handling |
<!-- departments:end -->

## Cops by Department

<!-- cops:start -->
### Lint

<details><summary>68 cops (click to expand)</summary>

| Cop | Description |
|---|---|---|
| Lint/ArrayShiftBeforeMatchCheck | Detects `Array#shift` followed by a conditional return that discards the shifted element. |
| Lint/BackoffWithoutJitter | Detects retry backoff calculations without randomization (jitter). |
| Lint/BreakInsteadOfNext | Detects `break` inside collection methods where `next` is intended. |
| Lint/BroadRescueInDomain | Detects overly broad rescue in domain/service code. |
| Lint/ChainedHashAccessWithoutDig | Detects chained hash `[]` access where `dig` is safer. |
| Lint/CompactStripsNilProxy | Detects `compact` on arrays that strip nil proxy objects. |
| Lint/ConcurrentPoolWithoutConnectionLimit | Detects connection pools without an explicit connection limit. |
| Lint/ConstantInsideMethod | Detects constants defined inside methods. |
| Lint/ConsumerEnsureSwallowsException | Detects explicit `return` in ensure blocks of consumer classes. |
| Lint/CssAttrValueWithoutGuard | Detects CSS attribute value access without nil guard. |
| Lint/CssFirstWithoutNilGuard | Detects `css(...).first` or `at_css` without a nil guard. |
| Lint/DateNewWithUnguardedArguments | Detects `Date.new` with arguments that may be invalid. |
| Lint/DeadExpressionBetweenSigAndDef | Detects orphaned expressions between a `sig` block and the following `def`. |
| Lint/DiscardedMethodResult | Detects method calls whose return value is discarded when it likely matters. |
| Lint/EnsureReturnMasksException | Detects explicit `return` in `ensure` that masks in-flight exceptions. |
| Lint/ErrorsAddWithoutEarlyReturn | Detects `errors.add` without a following early return. |
| Lint/FilterMapSideEffect | Detects side-effecting blocks passed to `filter_map`. |
| Lint/FindByBangInConsumerOrJob | Detects `find_by!` in consumer or job classes where the record may not exist. |
| Lint/FindByBangInJob | Detects `find_by!` in job classes where the record may not exist. |
| Lint/FindByBangOnOptionalLookup | Detects `find_by!` when the lookup is optional (nil is acceptable). |
| Lint/GlobalVariableFallback | Detects global variable fallback patterns that mask unset state. |
| Lint/HardcodedUuidInSource | Detects hardcoded UUIDs in source code that should be constants or config. |
| Lint/InsertAllNotUpsertAll | Detects `insert_all` used where `upsert_all` is needed for idempotency. |
| Lint/IvarMutexEagerInit | Detects mutex ivars that require eager initialization. |
| Lint/LostAtomicityFindEachUpdate | Detects `find_each` + `update` that lose atomicity under concurrent writes. |
| Lint/ModuleNeverIncluded | Detects modules that are never included or extended. |
| Lint/MutatingMethodNilReturn | Detects mutating methods that return nil, which can mask bugs. |
| Lint/NilChainingWithoutGuard | Detects method chaining on potentially nil receivers without a guard. |
| Lint/NilDefaultForBooleanParam | Detects `nil` as default for boolean-typed parameters. |
| Lint/NilElasticsearchIdBreaksUpsert | Detects nil Elasticsearch document IDs that break upsert operations. |
| Lint/NoStatusMarkers | Detects WIP/DONE/FIXME status markers in code. |
| Lint/NokogiriAttrValueNilChain | Detects chained attribute access on Nokogiri nodes that may return nil. |
| Lint/NokolexborCssFirstWithoutNilGuard | Detects `css(...).first` on Nokolexbor documents without nil guard. |
| Lint/OffByOneRetryComparison | Detects off-by-one errors in retry count comparisons. |
| Lint/OrOperatorWithFalsyFloat | Detects `\|\|` with falsy float values (0.0, NaN). |
| Lint/PaginationAccumulatorResetBug | Detects pagination accumulator patterns that silently reset. |
| Lint/PresentDropsBooleanFalse | Detects `present?` on boolean values, which drops false. |
| Lint/RaiseVariableNotBare | Detects `raise variable` instead of `raise "message"`. |
| Lint/RationaleRequiresOverturningCondition | Detects RATIONALE comments without an overturning condition. |
| Lint/RedundantArithmeticInLog | Detects unnecessary arithmetic inside log calls. |
| Lint/RegexSpaceInVerboseMode | Detects unescaped literal spaces in verbose-mode regexes. |
| Lint/RegexSpaceInVerboseModeBody | Detects unescaped spaces in verbose-mode regex body. |
| Lint/RescueDuplicatesTryBody | Detects rescue blocks that duplicate the body of the try block. |
| Lint/RescueLogsOnlyMessage | Detects rescue blocks that log only the exception message, losing the backtrace. |
| Lint/RescueReferencesUninitializedVariable | Detects local variables referenced in rescue that may not be initialized. |
| Lint/RescueSwallowsWithoutHandling | Detects rescue blocks that swallow exceptions without handling or logging them. |
| Lint/RescueUsesErrorInfoGlobal | Detects use of `$@`/`$!` instead of the bound exception variable. |
| Lint/RescueWithoutErrorTracking | Detects rescue blocks that catch exceptions without tracking them. |
| Lint/RescueWithoutExceptionBinding | Detects rescue blocks that catch exceptions without binding the exception object. |
| Lint/ResponseBracketAccessWithoutNilFallback | Detects bracket access on HTTP responses without nil fallback. |
| Lint/ReturnUnlessBangMethod | Detects `return unless` on bang methods where the return value is misleading. |
| Lint/SampleWithoutFallback | Detects `sample` on potentially empty collections without a fallback. |
| Lint/SampleWithoutNilGuardOnDynamicReceiver | Detects `sample` on a dynamic receiver that may be nil. |
| Lint/ServiceResultDataWithoutSuccessCheck | Detects accessing `data` on a ServiceResult without checking `success`. |
| Lint/ServiceResultNewInsteadOfFactory | Detects `ServiceResult.new` and recommends factory methods. |
| Lint/SilentRescueNoTrackNoRaise | Detects silent rescue blocks that neither track nor re-raise the exception. |
| Lint/SleepInCallbackBlocksHydra | Detects `sleep` inside Typhoeus::Hydra callback blocks. |
| Lint/SleepWithMagicNumber | Detects `sleep` with an unexplained magic number. |
| Lint/StaleRequirePath | Detects require paths that no longer resolve. |
| Lint/StateTransitionMissingUnknownStateGuard | Detects state transitions without a guard for unknown states. |
| Lint/SymbolKeyMergeIntoJsonb | Detects symbol-keyed hashes merged into jsonb columns. |
| Lint/TimeParseWithoutRescue | Detects `Time.parse` calls not wrapped in a rescue or safe parser. |
| Lint/TimeoutTimeoutInApp | Detects `Timeout.timeout` in application code. |
| Lint/UncapturedReturnValueInRescueScope | Detects return values in rescue blocks that are silently discarded. |
| Lint/UnderscorePrefixBreaksCaller | Detects underscore-prefixed method names that break caller expectations. |
| Lint/UnreachableAfterRaise | Detects code after `raise` that can never execute. |
| Lint/UpdateInAfterCallback | Detects `update` calls inside `after_*` callbacks. |
| Lint/WhileLoopWithoutIterationBound | Detects while loops with no guaranteed termination bound. |

</details>

### Rails

| Cop | Description |
|---|---|---|
| Rails/AfterCreateInsteadOfAfterCommit | Detects `after_create` used where `after_commit` is needed for side effects. |
| Rails/CrossDirectoryNamespaceSplit | Detects namespaces split between `app/models/` and `app/lib/`. |
| Rails/FindOrCreateByRaceCondition | Detects `find_or_create_by` race condition patterns. |
| Rails/IntegerBackedEnumOnly | Enforces integer-backed enums only. |
| Rails/LibAppBoundary | Detects `lib/` code that depends on `app/` code or vice versa. |
| Rails/NamespaceHome | Detects namespaces whose files are not in their canonical directory. |
| Rails/NonArCodeInModelsTopLevel | Detects non-ActiveRecord code at the top level of `app/models/`. |
| Rails/OneConstantPerFile | Detects files that define more than one constant. |
| Rails/RedundantNamespace | Detects single-file namespace wrapping that adds no value. |
| Rails/ResultToArrayFirst | Detects `result.to_a.first` where `result.first` suffices. |
| Rails/StrictLoadingBatch | Detects batch-loaded associations without `strict_loading`. |
| Rails/SyntheticActiveRecordMethod | Detects redefinition of ActiveRecord methods that hides the original. |
| Rails/UpdateColumnRequiresComment | Detects `update_column` calls without an explanatory comment. |

### Logging

| Cop | Description |
|---|---|---|
| Logging/AppropriateLogLevel | Detects log levels that are inappropriate for the message severity. |
| Logging/ConsistentRescueLogging | Enforces consistent logging patterns in rescue blocks. |
| Logging/LogThenRaise | Detects `raise` after log without re-raising context. |
| Logging/NoExtendLoggable | Detects `extend Loggable` (use `include Loggable` or class-level logger). |
| Logging/NoPutsPrintLogging | Detects `puts`/`print` used for logging output. |
| Logging/NoRailsLoggerInDomainCode | Detects `Rails.logger` in domain/service code. |
| Logging/NoStdlibLogger | Detects use of Ruby stdlib Logger instead of SemanticLogger. |
| Logging/NoStringInterpolationInLogCall | Detects string interpolation in log calls (use block form instead). |
| Logging/RescueLogLevelTooLow | Detects rescue blocks that log at too low a level for an exception. |
| Logging/SingleLineStructured | Enforces single-line structured log calls. |

### Sorbet

| Cop | Description |
|---|---|---|
| Sorbet/BlankLineBetweenSigilAndPragma | Detects blank lines between the `typed:` sigil and `frozen_string_literal:` pragma. |
| Sorbet/DuplicateSig | Detects duplicate `sig` declarations for the same method. |
| Sorbet/ExhaustiveUnionDispatch | Requires `T.absurd` in the else branch when dispatching over union types. |
| Sorbet/IsAUntypedAlwaysTrue | Detects `is_a?` checks on untyped values that always evaluate to true. |
| Sorbet/NoGemTypeInDomainReturn | Detects gem types in Sorbet `returns` annotations within domain code. |
| Sorbet/NoOptionsSplatInConstructor | Detects `**options` splats in constructors that bypass Sorbet typing. |
| Sorbet/NoTUnsafeVisibilityBypass | Detects `T.unsafe` used to bypass visibility modifiers. |
| Sorbet/SigParamNameMatchesDef | Detects sig parameter names that differ from the method definition. |
| Sorbet/UntypedIvarWithoutTLet | Detects untyped instance variables without `T.let` annotation. |
| Sorbet/UntypedRequiresJustification | Requires justification comments for `T.untyped` and `T.unsafe`. |

### MigrationSafety

| Cop | Description |
|---|---|---|
| MigrationSafety/AddCheckConstraintValidateFalse | Requires check constraints to be added without validation, then validated separately. |
| MigrationSafety/AddForeignKeyValidateFalse | Requires foreign keys to be added without validation, then validated separately. |
| MigrationSafety/AddIndexConcurrently | Requires concurrent index creation in migrations. |
| MigrationSafety/ChangeColumnNullRequiresValidation | Requires NOT NULL changes to follow the safe two-step pattern. |
| MigrationSafety/NoBackfillInSchemaMigration | Prevents data backfill in schema migrations. |
| MigrationSafety/RemoveColumnSafetyAssured | Requires explicit safety assurance when removing columns. |

A `SafeMigrationGenerator` is also included for generating migration files that comply with these cops.

### Test

| Cop | Description |
|---|---|---|
| Test/OrphanTestFile | Flags test files with no corresponding implementation file. |
| Test/RequireExpandedTestHelper | Requires the expanded test helper in test files that need it. |
| Test/RequireVcrForExternalHttp | Requires VCR for external HTTP requests in tests. |
| Test/RequireWithoutVcrHelper | Requires `WithoutVCR` helper for tests making real HTTP calls. |
| Test/StubLambdaKwargs | Detects lambda stubs that ignore keyword arguments. |
| Test/TestLocationMirrorsSource | Enforces that test files mirror their source file location. |

### Karafka

| Cop | Description |
|---|---|---|
| Karafka/ConsumerRescueWithoutReraise | Detects rescue blocks in Karafka consumers that swallow exceptions. |
| Karafka/KarafkaDoubleSerialization | Detects double serialization in Karafka message production. |
| Karafka/NoGlobalProducerAccess | Detects direct access to the global Karafka producer. |
| Karafka/PayloadToJsonBeforeProduce | Detects manual `to_json` before Karafka produce (double serialization). |
| Karafka/RequireSuperInConsume | Requires `super` in Karafka consumer `consume` methods. |

### Security

| Cop | Description |
|---|---|---|
| Security/ConstantizeFromUntrustedSource | Detects `constantize` on strings from untrusted sources. |
| Security/ContractParamsSliceLeak | Detects contract `params` slices that leak unrelated keys. |
| Security/NoDynamicSendFromVariable | Detects `send` with a variable method name from untrusted sources. |
| Security/ServiceResultErrorDisclosure | Detects ServiceResult error objects that leak internal details. |
| Security/SqlStringInterpolation | Detects string interpolation in SQL strings. |

### Style

| Cop | Description |
|---|---|---|
| Style/DuplicateBranchBody | Detects `if`/`else` branches with identical method call bodies. |
| Style/DuplicateMethodBody | Detects methods with structurally identical bodies. |
| Style/GuardClauseInversion | Detects guard clauses with inverted conditions. |
| Style/HashDeleteWithoutDup | Detects `hash.delete` without `dup` when the original is still needed. |
| Style/RedundantConditionalAfterGuard | Detects conditionals that are redundant after a guard clause. |

### Zeitwerk

| Cop | Description |
|---|---|---|
| Zeitwerk/NamespaceTableName | Detects namespaced models that must declare `self.table_name` due to Zeitwerk inference mismatch. |
| Zeitwerk/NoEscapingRequireRelative | Detects `require_relative` with escaping paths (`..`). |
| Zeitwerk/RedundantRequireRelative | Detects `require_relative` in `app/` where the target is autoloaded by Zeitwerk. |

### Performance

| Cop | Description |
|---|---|---|
| Performance/HashBuiltEveryCall | Detects a Hash literal returned inside a method body where the hash contains only static keys and values. |

### Secrets

| Cop | Description |
|---|---|---|
| Secrets/NoEnvFetchSecretFallback | Detects `ENV.fetch` with a fallback for secret values. |

### Service

| Cop | Description |
|---|---|---|
| Service/NoClassCallOverride | Detects `.call` overrides on service classes that break the call convention. |

### Time

| Cop | Description |
|---|---|---|
| Time/NoSystemTimeNow | Detects `Time.now` (use `Time.current` for timezone-aware time). |
<!-- cops:end -->

## Requirements

- Ruby >= 3.2
- RuboCop >= 1.50
- Sorbet Runtime (hard dependency)

## License

MIT
