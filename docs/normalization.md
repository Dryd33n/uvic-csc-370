# Functional dependencies and BCNF check

Owner: C (Eton)

## Method

For each table in our implemented schema (`sql/ddl.sql`): list the table's
functional dependencies, derive the candidate keys, and check that **every
determinant is a superkey**. A table is in BCNF exactly when, for every
nontrivial FD X → Y, X is a superkey.

## 1. user

Attributes: `user_id, name, email`

FDs:

- user_id → name, email (enforced by PRIMARY KEY)
- email → user_id (enforced by UNIQUE)

Candidate keys: {user_id}, {email}. Every determinant is a candidate key,
hence a superkey → **BCNF**.

## 2. stock

Attributes: `ticker, company_name, opening_price, closing_price, exchange`

FDs:

- ticker → company_name, opening_price, closing_price, exchange (PRIMARY KEY)

Candidate key: {ticker} → **BCNF**.

Note: `exchange` is currently a plain attribute (e.g. 'NASDAQ'), not its own
table. That means the exchange name repeats for every stock on the same
exchange — a known redundancy we accept for this sprint. Splitting it into an
exchange table (exchange_code → exchange_name) is planned; see the design docs
for the next-sprint schema.

## 3. transaction

Attributes: `transaction_id, user_id, ticker, transaction_type, quantity, price, time`

FDs:

- transaction_id → user_id, ticker, transaction_type, quantity, price, time (PRIMARY KEY)

Candidate key: {transaction_id} → **BCNF**.

`user_id` and `ticker` are foreign keys to `user` and `stock`, so every trade
references a real account and a real security. One row is one buy/sell event —
nothing about the user or the stock is repeated here beyond the keys.

## 4. holds

Attributes: `user_id, ticker, quantity, average_price`

FDs:

- user_id, ticker → quantity, average_price (PRIMARY KEY on both columns)

Candidate key: {user_id, ticker}. A user holds each stock at most once, so the
pair identifies the row → **BCNF**.

What we chose not to store: total position value. quantity × average_price is
computed by a query whenever it's needed — storing it would add a
non-key determinant and violate BCNF.

## Result

Every table passes: each FD's determinant is a superkey, so all 4 tables in
`sql/ddl.sql` are in BCNF. Goal 2's normalization criterion is met.

## Known limitations

- This doc covers the 4 implemented tables. The design docs
  (`docs/lossless-join.md`, `docs/dependency-preservation.md`) discuss a
  planned 10-table schema for the next sprint; when those tables land in the
  DDL, this check gets extended to cover them.
- These FDs come from our requirements and business rules. Goal A (formal FD
  analysis) will derive a proper minimal cover with attribute closures; if
  that cover comes out different, this doc gets redone.
