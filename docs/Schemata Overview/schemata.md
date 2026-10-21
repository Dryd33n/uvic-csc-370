# PaperTrade Schemata Overview

Reference for the eight relations in the PaperTrade schema: their attributes, keys, constraints, and relationships. Constraint IDs (`C.x.y`) are used consistently across the project docs.

| # | Table | Type |
|---|-------|------|
| 1 | `user` | Strong entity |
| 2 | `portfolio` | Strong entity (sub-account) |
| 3 | `exchange` | Strong lookup entity |
| 4 | `stock` | Strong entity |
| 5 | `stock_price_history` | Weak entity |
| 6 | `watchlist` | M : N relationship set with attributes |
| 7 | `transaction` | Immutable trade ledger entity |
| 8 | `limit_order` | Pending order entity |

---

## 1. `user`

A registered account holder. Stores profile details and the user's uninvested cash.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | `INT` | PK, auto increment |
| `name` | `VARCHAR(100)` | NOT NULL |
| `email` | `VARCHAR(255)` | NOT NULL, UNIQUE |
| `cash_balance` | `DECIMAL(12, 2)` | `>= 0`, default `100000.00` |

**Keys**
- Primary key: `user_id`
- Candidate key: `email`

**Constraints**
- C.1.1 `user_id` is the primary key. (PK)
- C.1.2 `email` is unique across all users. (UNIQUE)
- C.1.3 `name` and `email` are required. (NOT NULL)
- C.1.4 `email` must contain `@` and a domain. (CHECK `email LIKE '%_@_%._%'`)
- C.1.5 `cash_balance` can never be negative. (CHECK `cash_balance >= 0`)
- C.1.6 `cash_balance` defaults to a starting amount, e.g. `100000.00`. (DEFAULT)

**Relationships**
- 1 : N with `portfolio`: a user owns many portfolios.
- M : N with `stock` via `watchlist`: a user watches many stocks.

---

## 2. `portfolio`

A trading account owned by a user (e.g. "TFSA", "RRSP", "Day Trading"). Trades and orders are placed against a portfolio.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `portfolio_id` | `INT` | PK, auto increment |
| `user_id` | `INT` | FK → `user(user_id)`, NOT NULL |
| `portfolio_name` | `VARCHAR(100)` | NOT NULL, non-empty |
| `created_at` | `DATETIME` | default `CURRENT_TIMESTAMP` |

**Keys**
- Primary key: `portfolio_id`
- Candidate key: `(user_id, portfolio_name)`
- Foreign key: `user_id` → `user(user_id)` `ON DELETE CASCADE`

**Constraints**
- C.2.1 `portfolio_id` is the primary key. (PK)
- C.2.2 `user_id` must reference an existing user. (FK, NOT NULL)
- C.2.3 Deleting a user deletes their portfolios, watchlist entries and limit orders. The delete is refused if any of their portfolios has transactions (see C.7.11). (ON DELETE CASCADE)
- C.2.4 Portfolio names are unique per user; different users may reuse a name. (UNIQUE `(user_id, portfolio_name)`)
- C.2.5 `portfolio_name` is required and non-empty. (NOT NULL + CHECK `portfolio_name <> ''`)
- C.2.6 `created_at` defaults to insertion time. (DEFAULT CURRENT_TIMESTAMP)

**Relationships**
- N : 1 with `user`: each portfolio belongs to exactly one user.
- 1 : N with `transaction`: a portfolio logs many executed trades.
- 1 : N with `limit_order`: a portfolio places many orders.

---

## 3. `exchange`

A stock exchange where equities are listed (e.g. NASDAQ, NYSE, TSX).

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `exchange_code` | `VARCHAR(10)` | PK, uppercase |
| `exchange_name` | `VARCHAR(100)` | NOT NULL |
| `country` | `VARCHAR(50)` | NOT NULL |
| `currency` | `VARCHAR(10)` | NOT NULL, 3-letter ISO 4217 code |

**Keys**
- Primary key: `exchange_code`

**Constraints**
- C.3.1 `exchange_code` is the primary key. (PK)
- C.3.2 `exchange_name`, `country`, and `currency` are required. (NOT NULL)
- C.3.3 `currency` is a 3-letter ISO 4217 code, e.g. `USD`, `CAD`. (CHECK `CHAR_LENGTH(currency) = 3`)
- C.3.4 `exchange_code` is stored in uppercase. (CHECK `exchange_code = UPPER(exchange_code)`)

**Relationships**
- 1 : N with `stock`: an exchange lists many stocks.

---

## 4. `stock`

A tradeable public company equity listed on one exchange.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `ticker` | `VARCHAR(10)` | PK, uppercase |
| `company_name` | `VARCHAR(100)` | NOT NULL |
| `sector` | `VARCHAR(50)` | e.g. `'Technology'` |
| `exchange_code` | `VARCHAR(10)` | FK → `exchange(exchange_code)`, NOT NULL |

**Keys**
- Primary key: `ticker`
- Foreign key: `exchange_code` → `exchange(exchange_code)` `ON DELETE RESTRICT`

**Constraints**
- C.4.1 `ticker` is the primary key. (PK)
- C.4.2 `exchange_code` must reference an existing exchange. (FK, NOT NULL)
- C.4.3 An exchange can't be deleted while stocks are listed on it. (ON DELETE RESTRICT)
- C.4.4 `ticker` is stored in uppercase. (CHECK `ticker = UPPER(ticker)`)
- C.4.5 `company_name` is required. (NOT NULL)

**Relationships**
- N : 1 with `exchange`: each stock is listed on one exchange.
- 1 : N (identifying) with `stock_price_history`: a stock has many daily price records.
- M : N with `user` via `watchlist`.
- 1 : N with `transaction` (a stock with trades can't be deleted, C.7.11) and with `limit_order`.

---

## 5. `stock_price_history`

Daily market prices for a stock. Weak entity: a price record cannot exist without its owning `stock`.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `ticker` | `VARCHAR(10)` | PK (partial), FK → `stock(ticker)` |
| `price_date` | `DATE` | PK (partial), not in the future |
| `opening_price` | `DECIMAL(12, 4)` | `> 0`, between low and high |
| `closing_price` | `DECIMAL(12, 4)` | `> 0`, between low and high |
| `high_price` | `DECIMAL(12, 4)` | `> 0`, `>= low_price` |
| `low_price` | `DECIMAL(12, 4)` | `> 0` |
| `volume` | `BIGINT` | `>= 0` |

**Keys**
- Primary key: `(ticker, price_date)`
- Foreign key: `ticker` → `stock(ticker)` `ON DELETE CASCADE`

**Constraints**
- C.5.1 One price record per stock per day. (Composite PK)
- C.5.2 `ticker` must reference an existing stock; history is deleted with the stock. (FK, ON DELETE CASCADE)
- C.5.3 All four prices are positive. (CHECK `> 0` on each)
- C.5.4 Daily high is at least the daily low. (CHECK `high_price >= low_price`)
- C.5.5 Open and close fall within the low–high range. (CHECK `opening_price BETWEEN low_price AND high_price AND closing_price BETWEEN low_price AND high_price`)
- C.5.6 `volume` is non-negative. (CHECK `volume >= 0`)
- C.5.7 `price_date` can't be in the future. (Trigger; MySQL CHECKs can't call `CURDATE()`)

**Relationships**
- N : 1 with `stock`: identifying owner relationship.

---

## 6. `watchlist`

Stocks a user is monitoring, with an optional price alert threshold. Implements the M : N relationship between `user` and `stock`.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | `INT` | PK (part), FK → `user(user_id)` |
| `ticker` | `VARCHAR(10)` | PK (part), FK → `stock(ticker)` |
| `target_price` | `DECIMAL(12, 4)` | nullable, `> 0` if set |
| `added_at` | `DATETIME` | default `CURRENT_TIMESTAMP` |

**Keys**
- Primary key: `(user_id, ticker)`
- Foreign key: `user_id` → `user(user_id)` `ON DELETE CASCADE`
- Foreign key: `ticker` → `stock(ticker)` `ON DELETE CASCADE`

**Constraints**
- C.6.1 A user can watch a given stock only once. (Composite PK)
- C.6.2 `user_id` must reference an existing user; entry is deleted with the user. (FK, ON DELETE CASCADE)
- C.6.3 `ticker` must reference an existing stock; entry is deleted with the stock. (FK, ON DELETE CASCADE)
- C.6.4 `target_price`, if set, is positive. (CHECK `target_price > 0`, nullable)
- C.6.5 `added_at` defaults to insertion time. (DEFAULT CURRENT_TIMESTAMP)

**Relationships**
- N : 1 with `user`.
- N : 1 with `stock`.

---

## 7. `transaction`

The immutable ledger of every executed buy or sell. Holdings and cash movements are derived from this table.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `transaction_id` | `INT` | PK, auto increment |
| `portfolio_id` | `INT` | FK → `portfolio(portfolio_id)`, NOT NULL |
| `ticker` | `VARCHAR(10)` | FK → `stock(ticker)`, NOT NULL |
| `transaction_type` | `ENUM('buy', 'sell')` | NOT NULL |
| `quantity` | `INT` | `> 0` |
| `price` | `DECIMAL(12, 4)` | `> 0`, per share |
| `executed_at` | `DATETIME` | default `CURRENT_TIMESTAMP`, not in the future |

**Keys**
- Primary key: `transaction_id`
- Foreign key: `portfolio_id` → `portfolio(portfolio_id)` `ON DELETE RESTRICT`
- Foreign key: `ticker` → `stock(ticker)` `ON DELETE RESTRICT`

**Constraints**
- C.7.1 `transaction_id` is the primary key. (PK)
- C.7.2 `portfolio_id` and `ticker` must reference existing rows. (FK, NOT NULL)
- C.7.3 `quantity` is positive. (CHECK `quantity > 0`)
- C.7.4 `price` is positive. (CHECK `price > 0`)
- C.7.5 `transaction_type` is `'buy'` or `'sell'`. (ENUM, NOT NULL)
- C.7.6 Rows can't be updated or deleted once inserted. (BEFORE UPDATE / BEFORE DELETE triggers that SIGNAL)
- C.7.7 A buy's cost (`quantity × price`) can't exceed the owner's `cash_balance`. (Trigger or stored procedure)
- C.7.8 A sell can't exceed current holdings for that ticker (sum of buys − sum of sells in the portfolio). (Trigger or stored procedure)
- C.7.9 Each trade updates `user.cash_balance`: buys debit, sells credit. (AFTER INSERT trigger or procedure in a DB transaction)
- C.7.10 `executed_at` defaults to now and can't be in the future. (DEFAULT CURRENT_TIMESTAMP + trigger)
- C.7.11 A portfolio or stock that has transactions can't be deleted, so the ledger is never lost. This also blocks deleting a user who has traded. (ON DELETE RESTRICT on both FKs)

**Relationships**
- N : 1 with `portfolio`: each trade belongs to one portfolio.
- N : 1 with `stock`: each trade involves one ticker.

---

## 8. `limit_order`

An order waiting for a price threshold. When executed, it produces a matching `transaction` row.

**Attributes**

| Column | Type | Notes |
|--------|------|-------|
| `order_id` | `INT` | PK, auto increment |
| `portfolio_id` | `INT` | FK → `portfolio(portfolio_id)` |
| `ticker` | `VARCHAR(10)` | FK → `stock(ticker)` |
| `order_type` | `ENUM('buy', 'sell')` | NOT NULL |
| `target_price` | `DECIMAL(12, 4)` | `> 0` |
| `quantity` | `INT` | `> 0` |
| `status` | `ENUM('pending', 'executed', 'cancelled')` | default `'pending'` |
| `created_at` | `DATETIME` | default `CURRENT_TIMESTAMP` |

**Keys**
- Primary key: `order_id`
- Foreign key: `portfolio_id` → `portfolio(portfolio_id)` `ON DELETE CASCADE`
- Foreign key: `ticker` → `stock(ticker)` `ON DELETE CASCADE`

**Constraints**
- C.8.1 `order_id` is the primary key. (PK)
- C.8.2 `portfolio_id` and `ticker` must reference existing rows; orders are deleted with their parent. (FK, ON DELETE CASCADE)
- C.8.3 `target_price` and `quantity` are positive. (CHECK `> 0`)
- C.8.4 `order_type` is `'buy'` or `'sell'`. (ENUM, NOT NULL)
- C.8.5 `status` defaults to `'pending'`. (DEFAULT)
- C.8.6 Only pending orders can change status; `'executed'` and `'cancelled'` are final. (BEFORE UPDATE trigger)
- C.8.7 Marking an order `'executed'` creates a matching `transaction` row in the same DB transaction. (Trigger or stored procedure)
- C.8.8 Balance and holdings rules (C.7.7, C.7.8) are re-checked at execution, not only at placement. (Same trigger or procedure as C.8.7)
- C.8.9 `created_at` defaults to insertion time. (DEFAULT CURRENT_TIMESTAMP)

**Relationships**
- N : 1 with `portfolio`.
- N : 1 with `stock`.
