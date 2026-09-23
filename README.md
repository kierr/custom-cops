# custom-cops

A RuboCop extension with 135 cops covering lint, Rails, Sorbet, security, Karafka,
migration safety, logging, test structure, Zeitwerk, and more. Abstracted from a
large Rails monolith, distilling over a decade of production wisdom and insight.

Very much bespoke, published so others can cherry pick or learn from these patterns.

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

| Department | Cops | Focus |
|---|---|---|
| Lint | 68 | Code-quality and correctness |
| Rails | 13 | Rails conventions and safety |
| Sorbet | 10 | Type-system consistency |
| Logging | 10 | Structured logging conventions |
| MigrationSafety | 6 | Safe Postgres migrations |
| Test | 6 | Test structure and conventions |
| Karafka | 5 | Consumer and producer safety |
| Style | 5 | Code style and readability |
| Security | 5 | Security anti-patterns |
| Zeitwerk | 3 | Autoloading consistency |
| Performance | 1 | Performance anti-patterns |
| Secrets | 1 | Secret/credential handling |
| Service | 1 | Service object conventions |
| Time | 1 | Time handling |

## Cops by Department

### Lint

ArrayShiftBeforeMatchCheck, BackoffWithoutJitter, BroadRescueInDomain, ChainedHashAccessWithoutDig, CompactStripsNilProxy, ConcurrentPoolWithoutConnectionLimit, ConstantInsideMethod, ConsumerEnsureSwallowsException, CssAttrValueWithoutGuard, CssFirstWithoutNilGuard, DateNewWithUnguardedArguments, DeadExpressionBetweenSigAndDef, DiscardedMethodResult, EnsureReturnMasksException, ErrorsAddWithoutEarlyReturn, FilterMapSideEffect, FindByBangInConsumerOrJob, FindByBangInJob, FindByBangOnOptionalLookup, GlobalVariableFallback, GuardClauseInversion, HardcodedUuidInSource, InsertAllNotUpsertAll, IvarMutexEagerInit, LostAtomicityFindEachUpdate, ModuleNeverIncluded, MutatingMethodNilReturn, NilChainingWithoutGuard, NilDefaultForBooleanParam, NilElasticsearchIdBreaksUpsert, NoStatusMarkers, NokogiriAttrValueNilChain, NokolexborCssFirstWithoutNilGuard, OffByOneRetryComparison, OrOperatorWithFalsyFloat, PaginationAccumulatorResetBug, PresentDropsBooleanFalse, RaiseVariableNotBare, RationaleRequiresOverturningCondition, RedundantArithmeticInLog, RegexSpaceInVerboseMode, RegexSpaceInVerboseModeBody, RescueDuplicatesTryBody, RescueLogsOnlyMessage, RescueReferencesUninitializedVariable, RescueSwallowsWithoutHandling, RescueUsesErrorInfoGlobal, RescueWithoutErrorTracking, RescueWithoutExceptionBinding, ResponseBracketAccessWithoutNilFallback, ReturnUnlessBangMethod, SampleWithoutFallback, SampleWithoutNilGuardOnDynamicReceiver, ServiceResultDataWithoutSuccessCheck, ServiceResultNewInsteadOfFactory, SilentRescueNoTrackNoRaise, SleepInCallbackBlocksHydra, SleepWithMagicNumber, StaleRequirePath, StateTransitionMissingUnknownStateGuard, SymbolKeyMergeIntoJsonb, TimeParseWithoutRescue, TimeoutTimeoutInApp, UncapturedReturnValueInRescueScope, UnderscorePrefixBreaksCaller, UnreachableAfterRaise, UpdateInAfterCallback, WhileLoopWithoutIterationBound

### Rails

AfterCreateInsteadOfAfterCommit, CrossDirectoryNamespaceSplit, FindOrCreateByRaceCondition, IntegerBackedEnumOnly, LibAppBoundary, NamespaceHome, NonArCodeInModelsTopLevel, OneConstantPerFile, RedundantNamespace, ResultToArrayFirst, StrictLoadingBatch, SyntheticActiveRecordMethod, UpdateColumnRequiresComment

### Sorbet

BlankLineBetweenSigilAndPragma, DuplicateSig, ExhaustiveUnionDispatch, IsAUntypedAlwaysTrue, NoGemTypeInDomainReturn, NoOptionsSplatInConstructor, NoTUnsafeVisibilityBypass, SigParamNameMatchesDef, UntypedIvarWithoutTLet, UntypedRequiresJustification

### Security

ConstantizeFromUntrustedSource, ContractParamsSliceLeak, NoDynamicSendFromVariable, ServiceResultErrorDisclosure, SqlStringInterpolation

### Karafka

ConsumerRescueWithoutReraise, KarafkaDoubleSerialization, NoGlobalProducerAccess, PayloadToJsonBeforeProduce, RequireSuperInConsume

### MigrationSafety

AddCheckConstraintValidateFalse, AddForeignKeyValidateFalse, AddIndexConcurrently, ChangeColumnNullRequiresValidation, NoBackfillInSchemaMigration, RemoveColumnSafetyAssured

A `SafeMigrationGenerator` is also included for generating migration files that comply with these cops.

### Logging

AppropriateLogLevel, ConsistentRescueLogging, LogThenRaise, NoExtendLoggable, NoPutsPrintLogging, NoRailsLoggerInDomainCode, NoStdlibLogger, NoStringInterpolationInLogCall, RescueLogLevelTooLow, SingleLineStructured

### Test

OrphanTestFile, RequireExpandedTestHelper, RequireVcrForExternalHttp, RequireWithoutVcrHelper, StubLambdaKwargs, TestLocationMirrorsSource

### Style

DuplicateBranchBody, DuplicateMethodBody, HashDeleteWithoutDup, RedundantConditionalAfterGuard, BreakInsteadOfNext

### Zeitwerk

NamespaceTableName, NoEscapingRequireRelative, RedundantRequireRelative

### Performance

HashBuiltEveryCall

### Secrets

NoEnvFetchSecretFallback

### Service

NoClassCallOverride

### Time

NoSystemTimeNow

## Requirements

- Ruby >= 3.2
- RuboCop >= 1.50
- Sorbet Runtime (hard dependency)

## License

MIT
