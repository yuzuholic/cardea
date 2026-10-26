---
name: grdb
description: GRDB.swift (v7) best practices for SQLite in Swift — records, query interface, associations/joins, raw SQL, CTEs & window functions, migrations, ValueObservation, concurrency, full-text search (FTS5). Use when writing, reviewing, or debugging GRDB database code.
metadata:
  version: "1.1"
  grdb-version: "7.x (Swift 6.1+, iOS 13+, SQLite 3.20+)"
---

# GRDB.swift

GRDB is a toolkit for SQLite, not a managed-object ORM: records are plain value
structs with no identity map, no faulting, no auto-update, no thread tether.
Fetching is copying. SQL is a first-class citizen, never a hack.

## Reference files — read the relevant one before non-trivial work

- `references/records.md` — record protocols, Codable records, Columns,
  persistence methods/callbacks, upsert, RETURNING, Identifiable
- `references/querying.md` — query interface requests, expressions, operators,
  functions, associations entry points, embedding SQL snippets, custom requests,
  common table expressions & window functions
- `references/associations.md` — belongsTo/hasOne/hasMany/hasManyThrough,
  including vs joining, required vs optional joins, filtering/ordering through
  associations, nested & ad-hoc decoding, aggregates, FK ambiguity & self-joins
- `references/fts.md` — full-text search: FTS5 virtual tables, external-content
  sync triggers, safe FTS5Pattern building, MATCH queries, bm25 ranking,
  tokenizers (unicode61/porter/ascii), custom tokenizers
- `references/raw-sql.md` — execute/fetch with SQL, interpolation, arguments,
  rows/values/cursors, custom functions, collations, SQL injection
- `references/concurrency-observation.md` — DatabaseQueue vs DatabasePool,
  reader/writer capabilities, transactions, ValueObservation (incl. debugging),
  interrupt, memory management
- `references/values-and-gotchas.md` — value types (Date, UUID, Decimal, enums,
  JSON columns), error handling, and the full catalog of known pitfalls

## Non-negotiable rules

1. **Never embed values in SQL strings.** Use `?`/`:name` arguments or SQL
   interpolation (`execute(literal:)`, `SQLRequest("... \(value) ...")`) —
   interpolation is parameter-bound, not string concatenation.
2. **Pick the connection by need**: `DatabasePool` for apps (WAL, concurrent
   reads + one serialized writer); `DatabaseQueue` for tests/previews and
   in-memory databases. Both conform to `DatabaseReader`/`DatabaseWriter` —
   write code against the protocols.
3. **Narrow capabilities**: expose `any DatabaseReader` publicly, keep the
   writer private behind named mutation methods. `DatabaseWriter` inherits
   from `DatabaseReader`, so `var reader: any DatabaseReader { writer }` is a
   free upcast, and the compiler enforces who may write.
4. **Migrations are append-only history.** Never edit a shipped
   `registerMigration` block; add a new one. Use
   `eraseDatabaseOnSchemaChange = true` in DEBUG only.
5. **Records: struct + `Codable` + `FetchableRecord` + `MutablePersistableRecord`**
   (mutable + `didInsert` for auto-incremented keys; `PersistableRecord` when
   the key is not auto-incremented). Define `enum Columns` from `CodingKeys`:
   `static let name = Column(CodingKeys.name)` — rename-safe in both dialects.
6. **Database access closures must not nest** — connections are not reentrant
   (fatal error). Pass the `db` handle along instead.
7. **Cursors are lazy, single-pass, and thread-confined** to the access
   closure that made them. Never return a cursor out of `read { }`; return
   `fetchAll`/`fetchSet` results instead.
8. **When the query interface can't express it, write SQL** — `SQLRequest`
   decodes into the same record types and observes identically. Don't fight
   the builder; its supported shape is fixed (see querying.md).

## Quick skeleton (the blessed shape)

```swift
// Record
struct Player: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var score: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// Wrapper: one writer, migrations run at init, reads exposed
struct AppDatabase: Sendable {
    private let writer: any DatabaseWriter
    var reader: any DatabaseReader { writer }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }
}

// Read (observable)
let players = try await appDatabase.reader.read { db in
    try Player.order(\.score.desc).limit(10).fetchAll(db)
}

// Write (named verb, one transaction)
try await writer.write { db in
    try Player.filter { $0.team == "red" }.updateAll(db) { $0.score += 10 }
}

// Live UI
for try await players in ValueObservation
    .tracking { db in try Player.fetchAll(db) }
    .values(in: appDatabase.reader) {
    // fresh snapshot after every relevant commit
}
```

## High-frequency API recall

- Fetching: `fetchOne` / `fetchAll` / `fetchSet` / `fetchCursor`; counts via
  `fetchCount`; existence via `request.isEmpty(db)` and `Record.exists(db, id:)`
  (never count-and-compare).
- Persistence: `insert`, `update`, `updateChanges { }` (skips no-op UPDATEs),
  `save` (update-then-insert), `upsert`, `delete`; `*AndFetch` variants use
  SQLite `RETURNING` (iOS 15+).
- Batch: `updateAll(db) { $0.col.set(to: ...) }` (also `+=` etc.),
  `deleteAll`, `deleteOne(db, id:)`.
- Request building: `all/none/select/annotated/distinct/filter/matching/group/
  having/order/reversed/limit/joining/including/with`. `filter`+`having` chain
  with AND; `select`/`order`/`group`/`limit` REPLACE previous calls.
- Keys: `find` (throws if missing) vs `fetchOne(db, id:)` (optional);
  `filter(id:)`, `filter(keys:)` for requests.
- Async capture gotcha: `try player.insert(db)` on a captured `var` fails in
  Sendable closures — use `player = try player.inserted(db)`.

## Project-specific conventions (Alethia)

When working in the Alethia codebase, these additional rules apply on top:
raw SQL is legal ONLY in `Database/Migrations.swift` and named-request files;
repository verbs come in two forms (`(..., in db: Database)` composable
without transaction / `async` wrapper that owns one); cross-repository writes
compose db-level functions in a single `writer.write`; window-function views
(`best_chapter`) are always filtered by a PARTITION BY column; aggregates use
window-free views. If a file named `alethia-architecture` skill is present,
defer to it for structure questions.
