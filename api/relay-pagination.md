# Relay Pagination for List Endpoints

**Every list endpoint uses `RelayPage`, returns a `Connection` on 200 and a
`RelayPageError` on 400 through `MultiVerb`, executes a `SortSpec` keyset query, and
ships a conformance test proving that no row is skipped or duplicated.** Offset/limit is
not an accepted production pagination contract.

This standard was verified against the four `relay-pagination` 0.1.0.0 packages, their
upstream `v0.1.0.0` tag, and their Hackage releases on 2026-07-22. Re-check Hackage and
upstream tags before changing bounds.

## Use All Four Packages for Their Separate Jobs

```cabal
build-depends:
    relay-pagination             ==0.1.*
  , relay-pagination-servant     ==0.1.*
  , relay-pagination-hasql       ==0.1.*

test-suite service-test
  build-depends:
      relay-pagination-conformance ==0.1.*
```

The core package owns `Connection`, `Edge`, `PageInfo`, `PageRequest`, and opaque
cursors. The servant package owns the route combinator and its 400 wire error. The
hasql package owns keyset SQL and typed sort-key codecs. The conformance package walks a
real endpoint in both directions.

## Declare Validation and Both Responses in the Route

`RelayPage (defaultSize :: Nat) (maximumSize :: Nat)` declares the four query parameters
`first`, `after`, `last`, and `before`. Its `HasServer` instance validates them before a
handler runs and changes the handler input to one validated `PageRequest`.

```haskell
import Data.SOP (I (..), NS (..))
import Relay.Pagination (Connection)
import Relay.Pagination.Servant (RelayPage, RelayPageError)
import Servant.API.MultiVerb (AsUnion (..), MultiVerb, Respond)

type MemberPageResponses =
  '[ Respond 200 "Page of members" (Connection Member),
     Respond 400 "Invalid pagination" RelayPageError
   ]

data MemberPageResult
  = MemberPageOk !(Connection Member)
  | MemberPageBadRequest !RelayPageError

instance AsUnion MemberPageResponses MemberPageResult where
  toUnion = \case
    MemberPageOk page -> Z (I page)
    MemberPageBadRequest err -> S (Z (I err))
  fromUnion = \case
    Z (I page) -> MemberPageOk page
    S (Z (I err)) -> MemberPageBadRequest err
    S (S impossible) -> case impossible of {}

type ListMembersEndpoint =
  "members"
    :> RelayPage 20 100
    :> MultiVerb 'GET '[JSON] MemberPageResponses MemberPageResult

data MemberRoutes mode = MemberRoutes
  { listMembers :: mode :- ListMembersEndpoint
  }
  deriving stock (Generic)
```

Write `AsUnion` by hand, as required by [Servant API Design](./servant-routes.md). The
combinator rejects non-decimal sizes, malformed cursors, negative or oversized page
sizes, and mixed forward/backward arguments. It rejects oversize values rather than
clamping them. `first` with `last`, `after` with `before`, `first` with `before`, and
`last` with `after` are all invalid.

`RelayPageError` has `code`, `message`, `retryable`, and `parameter`. Its stable codes
are:

- `invalid_integer`;
- `invalid_cursor`;
- `mixed_pagination_directions`;
- `negative_page_size`; and
- `page_size_too_large`.

### The Recorded RFC 7807 Exemption

The combinator emits its own JSON `RelayPageError` before a handler runs. That released
wire contract is a protocol-mandated exemption from the fleet's RFC 7807 default. A
paginated endpoint uses `RelayPageError` for handler-detected cursor rejection too, so
one endpoint never has two different 400 bodies. Exempt these routes by name in the
[problem-details](./rfc7807-problem-details.md) conformance test.

## Treat Cursors as Opaque, Versioned Capabilities

`Cursor` is unpadded base64url over a `CursorPayload` containing the cursor format
version, a sort-spec fingerprint, and a list of typed keys. `KeyValue` is a closed sum:
integer, text, UUID, timestamp microseconds, boolean, or null. There is deliberately no
floating-point key. Timestamps are integer UTC microseconds so serialization cannot move
a boundary through rounding.

`sortSpecFingerprint` is 32-bit FNV-1a over each column expression, direction, and codec
tag. Changing any part of the order makes old cursors fail as `invalid_cursor`; never
silently reinterpret them under the new order. That rejection is part of safe API
evolution, not an availability bug.

Clients must not decode, edit, compare, or persist assumptions about the cursor payload.
They may store and return the opaque string.

## Make the Database Order Total

The hasql entry point is:

```haskell
paginate
  :: SortSpec row
  -> PageRequest
  -> Snippet
  -> Decoders.Row row
  -> Either CursorError (Statement () (Connection row))
```

A `SortSpec` is a non-empty list of `KeyColumn`s. Each column supplies trusted SQL text,
a direction, a Haskell extractor, and a typed codec.

```haskell
memberSort :: SortSpec Member
memberSort =
  SortSpec
    ( KeyColumn "created_at" Desc (\Member {createdAt} -> createdAt) timestamptzKey
        :| [KeyColumn "id" Asc (\Member {id = memberId} -> memberId) uuidKey]
    )
```

Three rules are mandatory and cannot be proved by the library:

1. The last sort column is unique per row, normally a primary key.
2. Every v1 sort column is `NOT NULL`.
3. `columnExpr` is trusted developer-authored SQL and never contains user input.

The built-in codecs are `int8Key`, `textKey`, `uuidKey`, `boolKey`, and
`timestamptzKey`. Create a matching composite btree index, including per-column
directions:

```sql
CREATE INDEX members_created_at_desc_id_asc
  ON members (created_at DESC, id ASC);
```

The base query contains filters but no `ORDER BY`, `LIMIT`, or cursor logic:

```haskell
baseQuery :: Snippet
baseQuery =
  Snippet.sql
    """
    SELECT id, name, email, created_at
    FROM members
    """
```

The engine wraps that query, adds an expanded lexicographic predicate, reverses
comparisons for backward pages, and fetches page size plus one probe row. Mixed sort
directions require the expanded form; a row-value comparison is wrong.

```text
SELECT * FROM (SELECT member_id, updated_at FROM members) AS rp_base
WHERE (updated_at < $1) OR (updated_at = $2 AND member_id > $3)
ORDER BY updated_at DESC, member_id ASC LIMIT $4
```

All cursor values and the limit are typed parameters. Cursors are minted in Haskell from
decoded rows through `mintCursor`, never assembled in SQL. Returned edges remain in the
canonical order for both forward and backward requests.

## Map Engine Rejection onto the Same 400

The combinator has already rejected malformed base64url. `paginate` returns `Left` when
the decoded cursor has the wrong fingerprint, key count, or key types, before any SQL
runs.

```haskell
listMembersHandler :: Connection -> PageRequest -> Handler MemberPageResult
listMembersHandler connection pageRequest =
  case paginate memberSort pageRequest baseQuery memberRowDecoder of
    Left cursorError ->
      pure (MemberPageBadRequest (cursorRejected pageRequest cursorError))
    Right statement ->
      liftIO (MemberPageOk <$> runDb connection (Session.statement () statement))
```

`cursorRejected` sets `code = "invalid_cursor"`, `retryable = False`, and identifies
`after` for a forward request or `before` for a backward request. Do not turn a client
cursor error into a database exception or a 500.

The runnable vertical is under `examples/members-server/src/Example/Members/` in the
relay-pagination repository: `Domain.hs` owns the in-memory canonical comparator,
`Api.hs` owns the route and result union, `Query.hs` owns `memberSort`, and `Handler.hs`
owns this mapping.

## A Conformance Test Is Part of the Endpoint

The test package reduces an endpoint to:

```haskell
type FetchPage row = PageRequest -> IO (Connection row)
```

Use `checkConformance` directly or its Tasty wrapper:

```haskell
testConformance
  :: (Ord key, Show key)
  => TestName
  -> ConformanceConfig
  -> (row -> key)
  -> FetchPage row
  -> IO [row]
  -> TestTree
```

The expected rows are the complete data set in canonical order, calculated independently
with a comparator that exactly mirrors the SQL `SortSpec`.

```haskell
canonicalOrder :: Member -> Member -> Ordering
canonicalOrder =
  comparing (\Member {createdAt} -> Down createdAt)
    <> comparing (\Member {id = memberId} -> memberId)
```

The suite checks six production invariants:

- `Completeness`: every expected row appears once and in order;
- `BackwardSymmetry`: forward and backward walks agree;
- `BoundaryHonesty`: continuation flags never promise a phantom page;
- `CursorDeterminism`: replaying a request reproduces the page;
- `EdgeOrderInvariance`: both directions return canonical edge order; and
- `PageInfoCursorConsistency`: start/end cursors match the boundary edges.

Seed duplicate values for every sort key except the unique tie-breaker, with a duplicate
group crossing a page boundary. All-distinct fixtures cannot catch the most common
non-total-order bug.

**An endpoint without this conformance test is not a paginated endpoint; it is a bug
generator with query parameters.** Prefer driving the typed servant client against a
real Warp application and test database, as `examples/members-server/test/Main.hs` does.

## Generate OpenAPI from the Same Route

Import `Relay.Pagination.Servant.OpenApi` in the one OpenAPI generator module. It is the
canonical home of the orphan instances that add all four query parameters, bounds, and
schemas to the derived document.

All four relay packages are published on Hackage at 0.1.0.0. That release bounds both
`openapi-hs` and `servant-openapi-hs` to the compatible `4.1.*` cohort. Follow those
bounds; do not force the current 5.x OpenAPI packages into a relay 0.1 build. A later
relay release may widen the cohort, so verify current registry metadata before pinning.

See [Generating the OpenAPI Document from Servant Types](./openapi-from-types.md) for
artifact generation, stable operation IDs, and document conformance tests.

## Related Patterns

- [Servant API Design](./servant-routes.md)
- [Generating the OpenAPI Document from Servant Types](./openapi-from-types.md)
- [RFC 7807 Problem Details for Error Bodies](./rfc7807-problem-details.md)
