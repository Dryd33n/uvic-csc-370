# Functional dependencies and BCNF check

Owner: C (Eton)

## Method

For each of the 10 tables in our planned schema: list the table's functional
dependencies, derive the candidate keys, and check that **every determinant is
a superkey**. A table is in BCNF exactly when, for every nontrivial FD X → Y,
X is a superkey.

Naming note: this doc uses `ticker` (matching `sql/ddl.sql` and the other
design docs). The video talking points say "symbol" — it's the same attribute.

## 1. app_user

Attributes: `user_id, username, email`

FDs:

- user_id → username, email (enforced by PRIMARY KEY)
- username → user_id (enforced by UNIQUE)
- email → user_id (enforced by UNIQUE)

Candidate keys: {user_id}, {username}, {email}. Every determinant is a
candidate key, hence a superkey → **BCNF**.

## 2. exchange

Attributes: `exchange_code, exchange_name, country`

FDs:

- exchange_code → exchange_name, country (PRIMARY KEY)

Candidate key: {exchange_code} → **BCNF**.

## 3. stock

Attributes: `ticker, company_name, sector, exchange_code`

FDs:

- ticker → company_name, sector, exchange_code (PRIMARY KEY)

Candidate key: {ticker} → **BCNF**.

What we chose not to store: `exchange_name`. Storing it in stock would add the
FD exchange_code → exchange_name, whose determinant is not a superkey of
stock. That is exactly why exchange is its own table (see Goal B for the
lossless chase on this split).

## 4. portfolio

Attributes: `portfolio_id, user_id, name, hidden`

FDs:

- portfolio_id → user_id, name, hidden (PRIMARY KEY)

Candidate key: {portfolio_id} → **BCNF**.

What we chose not to store: the owner's username or email. portfolio_id →
user_id, and user_id → username, email in app_user, so owner details are
already determined — storing them here would just duplicate app_user.

## 5. orders

Attributes: `order_id, portfolio_id, ticker, side, order_type, quantity, limit_price, status, placed_at`

FDs:

- order_id → portfolio_id, ticker, side, order_type, quantity, limit_price, status, placed_at (PRIMARY KEY)

Candidate key: {order_id} → **BCNF**.

## 6. trade

Attributes: `trade_id, order_id, fill_qty, fill_price, filled_at`

FDs:

- trade_id → order_id, fill_qty, fill_price, filled_at (PRIMARY KEY)

Candidate key: {trade_id} → **BCNF**.

What we chose not to store: `portfolio_id` and `ticker`. We already have
trade_id → order_id and order_id → portfolio_id, ticker (FD #7), so by
transitivity trade_id → portfolio_id, ticker. Storing them in trade would
duplicate what orders already says — every partial fill of one order would
repeat the same portfolio and ticker.

## 7. watchlist

Attributes: `watchlist_id, user_id, name`

FDs:

- watchlist_id → user_id, name (PRIMARY KEY)

Candidate key: {watchlist_id} → **BCNF**.

## 8. watchlist_item

Attributes: `watchlist_id, ticker, added_at`

FDs:

- watchlist_id, ticker → added_at (PRIMARY KEY on both columns)

Candidate key: {watchlist_id, ticker} → **BCNF**.

## 9. price_quote

Attributes: `ticker, quoted_at, price`

FDs:

- ticker, quoted_at → price (PRIMARY KEY on both columns)

Candidate key: {ticker, quoted_at} → **BCNF**.

## 10. portfolio_snapshot

Attributes: `portfolio_id, snapshot_date, cash, holdings_value`

FDs:

- portfolio_id, snapshot_date → cash, holdings_value (PRIMARY KEY on both columns)

Candidate key: {portfolio_id, snapshot_date} → **BCNF**.

What we chose not to store:

- `total_value`: the FD {cash, holdings_value} → total_value has a
  non-key determinant, so storing it would violate BCNF. Total value is
  computed as cash + holdings_value whenever it's needed.
- `rank`: a leaderboard rank is not determined by this row at all — it
  depends on _other_ rows (other portfolios' snapshots on the same date), so
  it can't be an FD of this table and is computed by a query instead.

## Result

Every table passes: each FD's determinant is a superkey, so all 10 tables
are in BCNF. Goal 2's normalization criterion is met.

## Known limitations

- These FDs come from our requirements and business rules. Goal A (formal FD
  analysis) will derive a proper minimal cover with attribute closures; if
  that cover comes out different, this doc gets redone.
- This doc covers the **planned** 10-table schema. The current `sql/ddl.sql`
  has 4 tables (`user`, `stock`, `transaction`, `holds`); the remaining six
  are planned for the next sprint, so until the DDL catches up this check is
  design-level evidence.
- Sector-level attributes (e.g. `sector`) are descriptive of the ticker and
  add no new determinants.
