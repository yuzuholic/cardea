# Connections, Concurrency, Observation

## DatabaseQueue vs DatabasePool

| | DatabaseQueue | DatabasePool |
|---|---|---|
| Access | serialized (capacity 1) | concurrent reads (default 5 readers) + 1 serialized writer |
| Journal | default (unless `journalMode = .wal`) | WAL automatically (unless readonly) |
| In-memory | ✅ (tests/previews) | ❌ |

App runtime → `DatabasePool`. Tests/previews → in-memory `DatabaseQueue`.
Both conform to `DatabaseReader`/`DatabaseWriter`; code against the protocols
and the two stay interchangeable. Snapshots: `DatabasePool.makeSnapshot()`
gives a frozen read-only view.

Opening (recommended file layout — dedicated subdirectory of Application
Support): create dir with FileManager, then
`DatabasePool(path:configuration:)`. Bundled resource DBs: open with
`config.readonly = true`. Connections close on deinit; explicit `close()` may
fail and produce zombies — read its docs before relying on it.

## Capability narrowing

`DatabaseWriter: DatabaseReader`. Store the writer privately, expose
`var reader: any DatabaseReader { writer }` — an upcast, not a second
connection. Readers can `read` and feed observations but cannot `write`:
least privilege enforced by types. A `DatabasePool` handed out as a reader
still routes reads to WAL reader connections.

## Access rules

- `read { db in }` / `write { db in }` are async-friendly
  (`try await writer.write { ... }`), each `write` is one transaction —
  the unit of atomicity AND the unit of observation notification.
- **Not reentrant**: nesting `dbQueue.write { dbQueue.write { } }` is a fatal
  error. Compose by passing `db` into `(Database) throws -> T` helper
  functions — the composable unit — and keep transaction-opening confined to
  the outermost wrapper.
- Leaving a transaction open at closure end is a fatal error unless
  `allowsUnsafeTransactions` (don't).
- Explicit control when needed: `db.beginTransaction()/commit()`, savepoints,
  `barrierWriteWithoutTransaction` (e.g. SQLCipher rekey), 
  `db.afterNextTransaction(onCommit:onRollback:)` for post-commit hooks.
- Swift 6 capture: mutating `insert` on a captured `var` won't compile in
  Sendable closures — `player = try await writer.write { [player] db in
  try player.inserted(db) }`.

## ValueObservation

```swift
let observation = ValueObservation
    .tracking { db in try Player.fetchAll(db) }   // ANY fetches; union is tracked
    .removeDuplicates()

// Swift concurrency
for try await players in observation.values(in: reader) { ... }
// Combine
observation.publisher(in: reader).sink(...)
// Callback
let cancellable = observation.start(in: reader, onError: ..., onChange: ...)
```

- The tracking closure may run SEVERAL fetches — all see one consistent
  snapshot; any write touching any read table re-runs the whole closure.
  This is the idiomatic way to compose DSL + SQLRequest results for a screen.
- First value is emitted immediately on start (`scheduling: .immediate`
  delivers it synchronously — good for avoiding empty first frames);
  subsequent values arrive on commit of relevant transactions.
- Observing views works: SQLite reports the underlying table reads.
- During write bursts (sync), observations re-fire per transaction — batch
  writes into fewer transactions and/or `.removeDuplicates()`.
- `trackingConstantRegion` is an optimization ONLY for requests whose tracked
  region never varies; when in doubt use `tracking`.

### Debugging "observation didn't fire" (from the FAQ)

1. Were changes actually committed? Trace SQL:
   `config.prepareDatabase { db in db.trace { print($0) } }`.
2. Were they immediately overwritten?
3. Was the observation cancelled / did it error? Add `.print()` to the
   observation and read the event log (`cancel`, `failure`, `value`).
4. Does the tracked region cover the change? The log prints regions like
   `player(id,name)[1]` (row 1), `player(*)`, `empty`. A region mismatch +
   `trackingConstantRegion` misuse → switch to `tracking`.

`DatabaseRegionObservation` exists for transaction-level (no value fetching)
notifications; `TransactionObserver` is the low-level protocol.

## Interrupt

`dbPool.interrupt()` aborts pending statements → they throw
`SQLITE_INTERRUPT`; statements inside a rolled-back wrapping transaction then
throw `SQLITE_ABORT` until the wrapper returns. Catch both:
`catch DatabaseError.SQLITE_INTERRUPT, DatabaseError.SQLITE_ABORT`.

## Memory

- `releaseMemory()` (blocking) / `releaseMemoryEventually()` (pool,
  non-blocking).
- iOS: automatic release on background/memory-warning
  (`automaticMemoryManagement`, default true).
- Each connection has its own page cache — `PRAGMA cache_size` multiplies by
  reader count.
- `persistentReadOnlyConnections = true` only if profiling shows connection
  churn.

## Multi-process (app group / widget) — future-proofing notes

Sharing a database file across processes is its own guide
("Sharing a Database"): requires app-group container, suspension handling
(`observesSuspensionNotifications` + posting suspend/resume around app
lifecycle) to dodge `0xDEAD10CC`, busy timeouts, and cross-process observation
via `DatabaseRegionObservation` + darwin notifications. None of it applies to
a single-process app; all of it applies the day a widget ships.

## Data protection / background

Locked-device file protection surfaces as `SQLITE_IOERR` / `SQLITE_AUTH`.
Catch and retry after `protectedDataDidBecomeAvailable`, or relax the file
protection level.
