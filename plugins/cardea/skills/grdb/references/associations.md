# GRDB — Associations

Declare relationships as static properties on `TableRecord` types, then build
joins with `including` / `joining`. Associations only produce the JOINs allowed
by the fixed query shape (see querying.md) — no arbitrary SQL. Foreign keys are
inferred from schema declarations unless ambiguous.

## Declaring associations

```swift
struct Book: TableRecord {
    static let author = belongsTo(Author.self)          // BelongsToAssociation
    static let library = belongsTo(Library.self)
    // hasOneThrough: reach through a belongsTo/hasOne pivot
    static let returnAddress = hasOne(Address.self, through: library, using: Library.address)
}

struct Author: TableRecord {
    static let books = hasMany(Book.self)               // HasManyAssociation
}

struct Country: TableRecord {
    static let demographics = hasOne(Demographics.self) // HasOneAssociation (1:1 denorm)
    static let passports = hasMany(Passport.self)
    // hasManyThrough: many-to-many via pivot
    static let citizens = hasMany(Citizen.self, through: passports, using: Passport.citizen)
}
```

**Direction:** `belongsTo` = this table holds the FK column. `hasMany`/`hasOne`
= the *other* table holds the FK. `through:` chains an existing association
(the pivot) with `using:` naming the onward link on the pivot.

**Pivot must declare both belongsTo legs:**

```swift
struct Passport: TableRecord {
    static let country = belongsTo(Country.self)
    static let citizen = belongsTo(Citizen.self)
}
```

## Self-joins & foreign-key ambiguity

`key:` disambiguates the association key (drives decode + default column
naming). `using: ForeignKey([...])` disambiguates *which FK column* when a
table has several pointing at the same target.

```swift
struct Employee: TableRecord {
    static let manager = belongsTo(Employee.self, key: "manager")
    static let subordinates = hasMany(Employee.self, key: "subordinates")
}

struct Book: TableRecord {
    static let authorFK = ForeignKey(["authorId"])
    static let translatorFK = ForeignKey(["translatorId"])
    static let author = belongsTo(Person.self, using: authorFK)
    static let translator = belongsTo(Person.self, using: translatorFK)
}
struct Person: TableRecord {
    static let writtenBooks = hasMany(Book.self, using: Book.authorFK)
}
```

## including vs joining, required vs optional

| Method | JOIN | Decodes associated row? | Missing → |
|--------|------|-------------------------|-----------|
| `including(required:)` | INNER | yes | row excluded |
| `including(optional:)` | LEFT | yes (as optional) | row kept, nil |
| `joining(required:)` | INNER | no (filter/order only) | row excluded |
| `joining(optional:)` | LEFT | no | row kept |

**Rule:** use `including` when you need the associated data in the result; use
`joining` only to filter/order by an associated table without selecting it.
`required` = INNER (both sides must exist), `optional` = LEFT.

```swift
// need author data:
let req = Book.including(required: Book.author)
// only filter by author, don't select them:
let frenchBooks = Book.joining(required: Book.author.filter { $0.country == "FR" })
```

## Filtering & ordering through associations

Refine the association itself with `.filter` / `.order` / `.select` before
passing it in. For cross-table WHERE comparing both tables, use a `TableAlias`.

```swift
// filter on associated column
Book.joining(required: Book.author.filter { $0.country == "FR" })

// order by associated column
Book.including(required: Book.author.order(\.name)).order(\.publishDate.desc)

// cross-table condition needs an alias
let author = TableAlias<Author>()
Book.joining(required: Book.author.aliased(author))
    .filter { $0.publishDate >= author.deathDate }
```

## Decoding into structs

Nested property names must match the **association key** (singular/plural of the
table name, or the `key:` / `.forKey(...)` override). Struct conforms to
`FetchableRecord, Decodable`.

```swift
struct BookInfo: FetchableRecord, Decodable {
    var book: Book
    var author: Author        // required → non-optional
    var country: Country?     // optional → optional
}
let req = Book.including(required: Book.author.including(optional: Author.country))
let infos = try BookInfo.fetchAll(db, req)
```

Rename a key with `.forKey` and target the request type explicitly:

```swift
let req = Book.including(required: Book.author.forKey("writer"))
    .asRequest(of: BookInfo.self)   // BookInfo.writer: Author
```

Ad-hoc row decoding when you want manual control:

```swift
struct BookInfo: FetchableRecord {
    var book: Book; var author: Author; var country: Country?
    init(row: Row) throws {
        book = try Book(row: row)
        author = try row.decode(forKey: "author")
        country = try row.decodeIfPresent(forKey: "country")
    }
}
```

## To-many: including(all:) — avoids N+1

`including(all:)` fetches the whole collection in a *second* batched query (not
one-per-parent), decoded into an array property. Prefer this over looping
`request(for:)` per parent.

```swift
struct AuthorInfo: FetchableRecord, Decodable {
    var author: Author
    var books: [Book]
}
let infos = try AuthorInfo.fetchAll(db, Author.including(all: Author.books))
```

Single record's related request (fine for one parent, N+1 in a loop):

```swift
extension Author {
    var books: QueryInterfaceRequest<Book> { request(for: Author.books) }
}
```

## Association aggregates

`annotated(with:)` appends aggregate columns; filter on them with `having()`
(NOT `filter` — aggregates need HAVING). HasMany / HasManyThrough only.
Aggregates: `.count`, `.isEmpty`, `.min(\.col)`, `.max`, `.average`, `.sum`,
`.total`. Default result key is auto-derived (`bookCount`, `maxBookYear`,
`hasNoBook`); override with `.forKey`.

```swift
struct AuthorInfo: FetchableRecord, Decodable {
    var author: Author
    var bookCount: Int
    var maxBookYear: Int?
}
let req = Author.annotated(with: Author.books.count, Author.books.max(\.year))

// filter on aggregate → having()
Author.having(Author.books.count >= 2)
Author.having(Author.books.isEmpty)

// combine / rename
let works = (Author.books.count + Author.paintings.count).forKey("workCount")
Author.annotated(with: works)
```

**Gotcha — distinct populations need distinct keys.** Two aggregates on the same
association with different filters must each get a unique `.forKey`, or they
collapse onto one population and return wrong numbers:

```swift
let novels = Author.books.filter { $0.kind == "novel" }.forKey("novels").count
let plays  = Author.books.filter { $0.kind == "play"  }.forKey("plays").count
Author.annotated(with: novels, plays)
```

## Gotchas

- `including` decodes; `joining` does not. Reaching for a `joining` result field
  means you wanted `including`.
- `required` = INNER JOIN can silently drop rows lacking the association — use
  `optional` unless absence should exclude.
- Association refinements `group`/`having`/aggregates apply to `including(all:)`,
  not `including(required:)`/`including(optional:)`.
- Loop of `request(for:)` per parent = N+1; use `including(all:)` instead.
- Nested decode property name must equal the association key exactly (respect
  pluralization and any `forKey`).
