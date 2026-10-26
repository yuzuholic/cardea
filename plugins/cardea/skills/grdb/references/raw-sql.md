# Raw SQL API

SQL is fully supported, injection-safe when arguments are used, and decodes
into the same record types as the DSL.

## Executing updates

```swift
try db.execute(sql: "INSERT INTO player (name, score) VALUES (?, ?)",
               arguments: ["Barbara", 1000])
try db.execute(sql: "UPDATE player SET score = :score WHERE id = :id",
               arguments: ["score": 1000, "id": 1])
try db.execute(literal: "INSERT INTO player (name, score) VALUES (\(name), \(score))")
let id = db.lastInsertedRowID     // after INSERT (records do this via didInsert)
```

- `?` positional / `:name` named arguments; interpolation via
  `execute(literal:)` is parameter-bound (NOT string building).
- Multiple statements joined by `;` run in order; fetching methods however
  require a SINGLE statement.
- **NEVER** `"... '\(value)' ..."` string interpolation into `sql:` — that is
  the injection vector (xkcd 327). The four safe forms: `?` array, `:name`
  dict, `execute(literal:)`, records/query interface.

## Fetching

Every fetchable type (Row, values, records) offers:
`fetchCursor` (lazy) / `fetchAll` ([T]) / `fetchSet` (Set<T>) / `fetchOne` (T?).

```swift
let rows = try Row.fetchAll(db, sql: "SELECT * FROM player WHERE name = ?", arguments: ["Arthur"])
let names = try String.fetchAll(db, sql: "SELECT name FROM player")
let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM player")!
let players = try Player.fetchAll(db, sql: "SELECT * FROM player")
```

`Int.fetchOne` returns nil BOTH for "no row" and "one NULL" — disambiguate
with `Optional<Int>.fetchOne(db, ...)` (a double optional: `.none` = no row,
`.some(.none)` = NULL row).

## Rows

```swift
let name: String  = row["name"]      // case-insensitive, leftmost match
let name: String? = row["name"]      // ask optional when NULL possible
let n: Int = row[0]                  // by index
let name: String? = row.coalesce(["nickname", "name"])  // NOT `??` between subscripts
```

- `row[...] as? Int` does NOT work — use `row[...] as Int?`.
- NULL into non-optional, or impossible conversions (e.g. "abc" as Date,
  256 as UInt8) are **fatal errors** — that's trusted-database philosophy. For
  untrusted content go through `DatabaseValue`:
  `if dbValue.isNull { } else if let d = Date.fromDatabaseValue(dbValue) { } else { }`
- Rows may contain duplicate column names (joins); subscript returns leftmost.
- Rows from a cursor are REUSED buffers: `row.copy()` before storing.
- Throwing accessors exist (`row.decode(String.self, forColumn:)`) but decoding
  errors are considered programming errors.

## Cursors

Lazy, direct SQLite access, minimal memory. Constraints:
- consume on the dispatch queue that created them → never escape the
  `read`/`write` closure (arrays/sets may escape freely);
- single-pass; don't mutate the DB mid-iteration; not a Swift `Sequence`
  (iteration can throw).
- Combinators available: map/filter/compactMap/reduce/prefix/…
- Feed collections: `Array(cursor)`, `Set(cursor)`,
  `Dictionary(grouping: cursor, by: { $0.teamID })`,
  `Dictionary(uniqueKeysWithValues: cursor.map { ($0.id, $0) })`.
- Rule of thumb: use `fetchAll` unless profiling says otherwise.

## Prepared statements

For hot paths or argument re-binding: `db.makeStatement(sql:)`,
`statement.setArguments(...)`, fetch from the statement. Also the safe route
for untrusted argument dictionaries (`StatementArguments(dict)` is failable).

## Custom SQL functions & aggregates

```swift
let reverse = DatabaseFunction("reverse", argumentCount: 1, pure: true) { values in
    String.fromDatabaseValue(values[0]).map { String($0.reversed()) }
}
config.prepareDatabase { db in db.add(function: reverse) }
// DSL usage: Player.select { reverse($0.name) }
```

Aggregates: type conforming to `DatabaseAggregate` (`init/step/finalize`),
registered the same way. Mark `pure: true` whenever result depends only on
inputs (enables SQLite optimizations). Functions may throw DatabaseError.

GRDB pre-ships unicode-aware `uppercase/lowercase/localized...` functions
(SQLite's UPPER/LOWER are ASCII-only).

## Collations (string comparison)

SQLite built-ins (binary, nocase, rtrim) are not unicode-aware. GRDB adds:
`unicodeCompare, caseInsensitiveCompare, localizedCaseInsensitiveCompare,
localizedCompare, localizedStandardCompare`.

```swift
t.column("email", .text).unique().collate(.nocase)
t.column("name", .text).collate(.localizedCaseInsensitiveCompare)
Player.order { $0.name.collating(.localizedCaseInsensitiveCompare) }
```

Custom: `DatabaseCollation("name") { lhs, rhs in ... }` added in
`prepareDatabase`. **Warning:** non-built-in collations baked into the schema
make the file non-portable to other SQLite hosts (Android port, CLI tools) —
prefer request-level collation when the file must travel.

## Raw SQLite pointers

`db.sqliteConnection`, `statement.sqliteStatement` expose the C API
(`import SQLite3` / `import SQLCipher`). GRDB owns them (never close/finalize),
they're multi-thread-mode = NOT thread-safe, use only inside access closures.

## LIKE argument gotcha

`LIKE '%?%'` fails ("wrong number of statement arguments") — `?` inside a
string literal is just a character. Bind the whole pattern:
`... name LIKE ?`, `arguments: ["%\(name)%"]`.

## Double-quote gotcha

Standard SQL uses `'single quotes'` for strings; `"double"` quotes are
identifiers. Old SQLite tolerated `"string"` literals; modern SQLite +
GRDB's default `acceptsDoubleQuotedStringLiterals = false` reject them —
which converts silent typo-matching into a loud
`SQLite error 1 no such column`. Keep the default; fix the quotes.
