# Values, Schema, Errors, Pitfalls

## Supported value types

Standard library (Bool, all int types, Double/Float, String, RawRepresentable
enums), Foundation (Data, Date, DateComponents, Decimal, NSNumber, URL, UUID),
CGFloat, FTS patterns, and anything conforming to `DatabaseValueConvertible`.

### Dates

Default storage: `"YYYY-MM-DD HH:MM:SS.SSS"` UTC string — chosen because it is
comparable (`ORDER BY`), comparable with `CURRENT_TIMESTAMP`, feeds SQLite
date functions, millisecond-precise. Numeric values decode as unix timestamps.

- Valid year range 0000–9999; outside it, decoding/date functions break.
- ISO-8601-with-timezone storage breaks database-level comparison — resist
  the "same format as my JSON" instinct.
- Custom formats via Codable strategies:
  `static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { .timeIntervalSince1970 }`
  (+ decoding twin). Strategies apply to persistence AND key-based requests
  (`filter(id:)`), but NOT to hand-built expressions — encode values yourself
  there.
- `DatabaseDateComponents` stores partial dates (`.YMD`, `HH:MM`, …).

### UUID

Stored as 16-byte BLOB by default; decodes blobs and uuid strings. Strategy
`.uppercaseString` switches storage to text. **Pitfall:** with string storage,
`filter { $0.id == uuid }` builds a BLOB comparison and finds nothing —
`filter(id:)` honors the strategy; raw expressions need `uuid.uuidString`.

### Decimal / NSDecimalNumber / NSNumber

- `Decimal` writes decimal STRINGS (exact, but strings in the DB);
  reads ints/doubles/strings.
- `NSNumber`/`NSDecimalNumber` write int64/double — non-integer
  NSDecimalNumber loses precision through double.
- Money/chapter-number-style exact values: store scaled INTEGERs
  (cents; milli-units) — the recommendation straight from the docs.

### Enums

`enum Color: Int` / `enum Grape: String` + `extension: DatabaseValueConvertible {}`.
Unmatched raw value in a non-optional decode = fatal error; go through
`DatabaseValue` + `fromDatabaseValue` for lenient handling.

### JSON columns

Codable record properties that aren't plain values are stored as JSON text
automatically (JSONEncoder: base64 Data, millisecondsSince1970 dates).
Set `sortedKeys` on any custom encoder — stable output is REQUIRED for
`removeDuplicates()`/record comparison to behave. Customize via
`databaseJSONDecoder(for:)` / `databaseJSONEncoder(for:)`.

### Data

Blob columns ↔ `Data`. Zero-copy read inside an iteration step:
`row.withUnsafeData(name:) { data in ... }` (must not escape the step).

## Schema & migrations quick notes

- `db.create(table:)` DSL: `t.autoIncrementedPrimaryKey("id")`,
  `t.primaryKey("isoCode", .text)`, `.notNull()`, `.unique()`,
  `.indexed()`, `.references(..., onDelete: .cascade)`, `.collate(...)`,
  `.check(...)`, `.defaults(to:)`; `create(index:)`, partial indexes via SQL.
- Raw `db.execute(sql: "CREATE …")` equally legitimate inside migrations
  (views, triggers, FTS require it).
- Migrations run in registration order, each in its own transaction;
  foreign-key checks can be deferred per-migration when reshaping tables.
- NEVER modify a shipped migration; append. `#if DEBUG
  eraseDatabaseOnSchemaChange` for development only.

## Error handling

- `DatabaseError`: `resultCode` (primary), `extendedResultCode` (e.g.
  `SQLITE_CONSTRAINT_FOREIGNKEY` refines `SQLITE_CONSTRAINT`), `message`,
  `sql`, `arguments` (arguments only shown when `publicStatementArguments`).
  Pattern-matchable: `catch DatabaseError.SQLITE_CONSTRAINT_FOREIGNKEY`.
  Extended codes vary by SQLite version — match with care.
- `RecordError.recordNotFound(databaseTableName:key:)` — from `update` on a
  missing row and from `find`.
- `RowDecodingError` — decoding failures via throwing accessors.
- Fatal errors are deliberate for programmer errors: NULL into non-optional,
  impossible conversions, `deleteOne(key:)` without a unique index,
  reentrant access, unclosed transactions. Untrusted DB content → go through
  `DatabaseValue`; untrusted arguments → failable `StatementArguments(dict)` +
  prepared statement.
- Global SQLite log: `Database.logError = { code, message in ... }` — must be
  set BEFORE any connection anywhere opens; it's process-global.

## Configuration essentials

`foreignKeysEnabled` (default true), `readonly`, `label` (names connections +
dispatch queues for debugging), `prepareDatabase { db in }` (runs per
connection — pragmas, trace, functions, collations, SQLCipher passphrase;
distinguish readers via `db.configuration.readonly`),
`publicStatementArguments` (DEBUG only — privacy),
`busyMode`, `maximumReaderCount`, `qos`, `automaticMemoryManagement`,
`acceptsDoubleQuotedStringLiterals` (keep false),
`observesSuspensionNotifications` (multi-process only). Profiling:
`db.trace(options: .profile) { event in ... }` exposes per-statement duration.

## Encryption (SQLCipher)

`config.prepareDatabase { db in try db.usePassphrase(...) }` — load the
passphrase INSIDE the closure (it runs per new connection; also limits
lifetime in memory; Data + `resetBytes` for stricter hygiene). Rekey on a
pool inside `barrierWriteWithoutTransaction` + `invalidateReadOnlyConnections`.
Encrypting an existing plaintext file requires `sqlcipher_export` into a new
database — a passphrase alone throws "file is encrypted or is not a database".
Pool connections open lazily: keychain-protected passphrases can make random
later reads fail when the device locks.

## Backup

`try source.backup(to: destination)` (queue or pool, either direction —
including in-memory ⇄ file). Optional `pagesPerStep` + `progress` callback;
throwing from progress before completion aborts the backup.

## Pitfall catalog (fast scan before review sign-off)

1. `order()` silently replaces earlier `order()`; `filter()` ANDs.
2. Cursor escaped from access closure / iterated twice / rows not copied.
3. `row[...] as? Int` (broken) vs `row[...] as Int?` (correct);
   `row["a"] ?? row["b"]` (broken) vs `row.coalesce(["a","b"])`.
4. `Int.fetchOne` nil ambiguity → `Optional<Int>.fetchOne` double optional.
5. LIKE `'%?%'` → bind whole pattern.
6. Double-quoted string literals → single quotes.
7. `Identifiable` on `Int64?` auto-increment ids.
8. `databaseSelection` / `databaseDecodingUserInfo` missing explicit type
   annotation → protocol requirement silently unfulfilled.
9. String `+` in expressions is numeric — use `.concat`.
10. UUID/date strategy vs hand-built expression mismatch.
11. Non-integer NSDecimalNumber precision loss; prefer scaled Int or Decimal.
12. `didInsert` garbage rowid under `.ignore` conflict policy.
13. Persistence callbacks not firing for batch ops / raw SQL — triggers or
    explicit code needed there.
14. `did***` callbacks run pre-commit — use `afterNextTransaction` for side
    effects.
15. Custom collation baked into schema = file not portable off-GRDB.
16. Reentrant `write { write { } }` fatal error.
17. Mutating `insert` on captured var in Sendable closure → `inserted(db)`.
18. Extended result codes differ across OS SQLite versions.
19. `.replace` conflict policy deletes invisibly to transaction observers.
20. Multi-statement SQL string passed to a fetch method (single statement
    required — iterate prepared statements instead).
