# Query Interface

Swift request builder over a **fixed SQL shape**:
`WITH / SELECT / FROM (one table) / JOIN (associations only) / WHERE / GROUP BY / HAVING / ORDER BY / LIMIT`.
Anything outside that shape (window functions, subquery-around-window, multi-
statement…) is raw-SQL territory — see raw-sql.md. Requests start from a
`TableRecord` type, or `Table("name")` / `Table<Player>("name")` when no
record type exists.

## Builder methods

```swift
Player.all()                                  // SELECT *
Player.none()                                 // never matches (useful guard value)
Player.select(\.name, as: String.self)
Player.selectID()                             // Identifiable only
Player.annotated { ($0.score + $0.bonus).forKey("total") }   // extend selection
Player.select { max($0.score) }
Player.select(\.name, as: String.self).distinct()
Player.filter { $0.name != nil && $0.height > 1.75 }
Player.filter(id: 1) / .filter(ids:) / .filter(key:) / .filter(keys:)
Document.matching(pattern)                    // FTS3/FTS5 MATCH
Player.select { [$0.team, max($0.score)] }.group(\.team).having { min($0.score) >= 1000 }
Player.order(\.score.desc)                    // NULLs sort first asc / last desc
Player.order { [$0.score.desc, $0.name] }.reversed()
Player.limit(5, offset: 10)
Player.including(required: Player.team)       // associations: join + decode
Player.with(cte)                              // common table expressions
Player.orderByPrimaryKey() / .groupByPrimaryKey() / .selectPrimaryKey(as:)
```

**Chaining semantics (bug factory):** `filter`, `matching`, `having` EXTEND
(AND). `select`, `order`, `group`, `limit` REPLACE any previous call of the
same kind. `reversed()` with no ordering is a no-op.

## Expressions

Operators map from Swift: `== != === !== < <= > >=` (== nil → IS NULL),
arithmetic `* / + -`, bitwise `& | ~ << >>`, logical `&& || !`.

- Sequence folding: `[a, b, c].joined(operator: .add / .multiply / .and / .or / .concat)`
  (empty: 0 / 1 / true / false / ""). Raw constants inside need
  `.databaseValue`: `[$0.score, 1000.databaseValue].joined(operator: .add)`.
- String concat is `.concat`, NOT `+` (`+` is numeric addition in SQLite).
- Ranges/collections: `[1,2,3].contains($0.id)`, `(0...1000).contains($0.score)`,
  negation with `!`.
- Subqueries compose: a request or `SQLRequest` used as a value
  (`$0.score == maximumScore`) or via `.contains($0.id)` (IN), `.exists()` /
  `!request.exists()` (EXISTS) with `TableAlias` for correlated references:

```swift
let teamAlias = TableAlias<Team>()
let player = Player.filter { $0.teamId == teamAlias.id }
let teamsWithPlayers = Team.aliased(teamAlias).filter(player.exists())
// self-join disambiguation: TableAlias<Player>(name: "coach")
```

- `LIKE`: `$0.email.like("%@example.com")` (case-insensitive, not
  unicode-aware; escape param available).
- `AS`: `.forKey("total")`; refer to it later with a *detached* column:
  `.order(Column("total").detached)`.
- Functions: `abs, average, coalesce, count, count(distinct:), dateTime,
  julianDay, length, min, max, sum, total, cast($0.wins, as: .real)`.
  `??` → IFNULL. Avoid SQLite `UPPER/LOWER` (not unicode-aware) — GRDB ships
  Swift-backed `uppercased()` etc.; for *comparisons* prefer collations:
  `$0.name.collating(.caseInsensitiveCompare) == name`.

## Fetching from requests

```swift
try request.fetchAll(db) / fetchOne / fetchSet / fetchCursor / fetchCount
try request.isEmpty(db)                       // prefer over fetchCount == 0

// fetch other types:
let maxScore = try Int.fetchOne(db, Player.select { max($0.score) })
let request = Player.select({ max($0.score) }, as: Int.self)   // typed request
let request = Book.including(required: Book.author).asRequest(of: BookInfo.self)
```

Composite decodable for association requests:

```swift
struct BookInfo: Decodable, FetchableRecord {
    var book: Book        // property names match association keys
    var author: Author    // (override with .forKey("..."))
}
```

`including(required:/optional:)` = JOIN + nested decode;
`joining(required:/optional:)` = JOIN without selecting;
`including(all:)` = prefetch via a second `WHERE … IN` query (to-many);
`annotated(with: Assoc.count)` = aggregate annotation;
`annotated(withRequired/Optional: assoc.select { ... })` = single associated
columns. Full association DSL: see AssociationsBasics in GRDB docs.

Anti-join idiom (records WITHOUT an associated record):

```swift
let a = TableAlias<Author>()
Book.joining(optional: Book.author.aliased(a)).filter(!a.exists)
```

## Embedding SQL snippets inside DSL requests

Every clause accepts raw SQL, interpolation, or mixed forms:

```swift
Player.select(sql: "IFNULL(name, ?), score", arguments: [defaultName])
Player.filter(literal: "score >= \(minScore)")           // safe interpolation
Player.select {
    let displayName = SQL("IFNULL(\($0.name), \(defaultName))").sqlExpression
    return [displayName.forKey("displayName"), $0.score]
}
// Reusable missing-function shims:
func date(_ value: some SQLSpecificExpressible) -> SQLExpression {
    SQL("DATE(\(value))").sqlExpression
}
Player.filter { date($0.createdAt) == "2020-01-23" }
```

Orderings embedded as SQL must be `.sqlExpression` literals to support
`.desc`/`reversed()`. `FROM`, `JOIN`, `LIMIT` cannot be customized — if you
need to, use `SQLRequest`.

## Custom requests

```swift
extension Player {
    static func filter(color: Color) -> SQLRequest<Player> {
        "SELECT * FROM player WHERE color = \(color)"     // SQLRequest via interpolation
    }
}
```

`SQLRequest` fetches, counts, and observes exactly like a
`QueryInterfaceRequest`. Named request functions (dialect hidden inside) are
the recommended seam between DSL and SQL. `adapted(_:)` + `RowAdapter` exist
for slicing complex joined rows manually.

Don't rely on the exact SQL text GRDB generates — it may change between
releases. Debug output: `try request.makePreparedRequest(db).statement`
prints SQL + arguments.

## Common table expressions & window functions

Define a CTE from a request or raw SQL, then attach with `.with(cte)`:

```swift
let cte = CommonTableExpression(named: "playerName", request: Player.select(\.name))
let cte = CommonTableExpression(named: "playerName", sql: "SELECT ?", arguments: [name])
let cte = CommonTableExpression(named: "pair", columns: ["a", "b"], sql: "SELECT 1, 2")
```

`.with(cte)` prepends `WITH`; the CTE is inert until referenced. Reference it
as a value (`cte.all()`) or via an association:

```swift
Player.with(cte).filter { $0.name == cte.all() }        // subquery value
let assoc = Player.association(to: cte, on: { player, c in player.id == c["playerId"] })
Player.with(cte).including(required: assoc)              // JOIN + nested decode
```

`association(to:on:)` closure receives `(base, cte)` table aliases; subscript
the CTE with `Column` since it has no record type. Decode like any
association request (property key matches the CTE name, override via `.forKey`).

**Recursive** — set `recursive: true`, list `columns:`, seed with `UNION ALL`:

```swift
let counter = CommonTableExpression(
    recursive: true, named: "counter", columns: ["x"],
    sql: "VALUES(1) UNION ALL SELECT x+1 FROM counter WHERE x < 1000")
Int.fetchAll(db, Table("counter").with(counter))
```

**Window functions:** no query-interface builder exists. Express them in raw
`SQL`/`SQLRequest`, or — for a reused ranked-row shape — bake a window into a
database VIEW in a migration (the `best_chapter`-style `PARTITION BY` VIEW
convention) and map that VIEW to a `TableRecord`. Raw shape decoding into a
record:

```swift
let request: SQLRequest<ScoredPlayer> = """
    SELECT *, RANK() OVER (PARTITION BY teamId ORDER BY score DESC) AS rank
    FROM player
    """
let ranked = try request.fetchAll(db)                   // ScoredPlayer: FetchableRecord
```

CTEs compose with window functions: wrap the windowed SELECT in a CTE, then
filter the outer request (`WHERE rank = 1`) — the query interface can't filter
a window column directly.
