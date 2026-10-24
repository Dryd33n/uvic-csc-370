-- Goal D queries for the stock_trading schema
--   Run after ddl.sql and seed.sql. Read-only: nothing here changes the data.
--   Q1, Q3-Q6, Q8, Q10 and Q11 are written; the rest are still outlines.
--   The written queries use the views in sql/views.sql, so run that first
--   (Docker and CI load it after the seed).
--   CI runs this file, so it must stay valid SQL.
--
-- Shared definitions (used by many queries below; now views in sql/views.sql)
--   Latest price  For each ticker, the closing_price on its most recent
--                 price_date in stock_price_history (MAX(price_date) per ticker).
--   Holdings      There is no holdings table: shares held are derived from the
--                 ledger per (portfolio_id, ticker) as
--                 SUM(buy quantity) - SUM(sell quantity). Keep rows > 0.
--   Cost basis    Average buy price per (portfolio_id, ticker):
--                 SUM(buy quantity * price) / SUM(buy quantity). Approximate if a
--                 position was fully sold and then bought again.
--   Market value  shares held * latest price.
--   Starting cash 100000.00 per user (C.1.6 default; the seed generator uses it).
--   Currency      Prices are in the exchange's currency (USD for NASDAQ/NYSE,
--                 CAD for TSX), so sums across exchanges mix currencies.

USE stock_trading;

-- -----------------------------------------------------
-- Q1: Current holdings per portfolio
-- -----------------------------------------------------
-- For each portfolio: owner name, portfolio_name, ticker, company_name,
-- shares held, cost basis, latest price, market value and unrealized
-- gain/loss ((latest price - cost basis) * shares held).
-- Joins: user JOIN portfolio JOIN transaction (aggregated per portfolio and
-- ticker) JOIN stock JOIN latest price. Skip positions with 0 shares.
-- Order by user, portfolio, then ticker.
-- Large result, so only the first 15 rows are shown; remove LIMIT for all.
SELECT u.name,
       p.portfolio_name,
       v.ticker,
       s.company_name,
       v.shares,
       ROUND(v.cost_basis, 2)      AS cost_basis,
       v.latest_price,
       ROUND(v.market_value, 2)    AS market_value,
       ROUND(v.unrealized_gain, 2) AS unrealized_gain
FROM v_position_value AS v
JOIN portfolio        AS p ON p.portfolio_id = v.portfolio_id
JOIN `user`           AS u ON u.user_id      = v.user_id
JOIN stock            AS s ON s.ticker       = v.ticker
ORDER BY u.user_id, p.portfolio_name, v.ticker
LIMIT 15;

-- -----------------------------------------------------
-- Q2: Trade history for one user
-- -----------------------------------------------------
-- Every transaction in all of one user's portfolios (e.g. user_id = 1),
-- newest first: executed_at, portfolio_name, ticker, company_name,
-- transaction_type, quantity, price and the trade total (quantity * price).
-- Joins: portfolio JOIN transaction JOIN stock, filtered on user_id.

-- -----------------------------------------------------
-- Q3: Leaderboard
-- -----------------------------------------------------
-- Rank users by net worth: cash_balance + market value of every holding in
-- all of their portfolios. Also show the gain over the starting cash
-- (net worth - 100000.00).
-- Joins: user LEFT JOIN (holdings across portfolios JOIN latest price), so
-- users with no holdings still appear with just their cash.
-- RANK() OVER (ORDER BY net worth DESC).
-- Only the top 10 are shown; remove LIMIT for all 420 users.
SELECT RANK() OVER (ORDER BY u.cash_balance + COALESCE(pv.market_value, 0) DESC) AS place,
       u.name,
       u.cash_balance,
       ROUND(COALESCE(pv.market_value, 0), 2)                         AS holdings_value,
       ROUND(u.cash_balance + COALESCE(pv.market_value, 0), 2)        AS net_worth,
       ROUND(u.cash_balance + COALESCE(pv.market_value, 0) - 100000.00, 2) AS gain
FROM `user` AS u
LEFT JOIN (SELECT user_id, SUM(market_value) AS market_value
           FROM v_position_value
           GROUP BY user_id) AS pv ON pv.user_id = u.user_id
ORDER BY place
LIMIT 10;

-- -----------------------------------------------------
-- Q4: Trading activity per stock
-- -----------------------------------------------------
-- For each stock: number of trades, buys vs. sells, total shares traded,
-- total dollar volume (SUM(quantity * price)) and number of distinct
-- portfolios that traded it.
-- Uses LEFT JOIN from stock so stocks with no trades show zeros.
-- GROUP BY ticker, order by trade count descending.
-- Expected with the committed seed: 14 rows; ATD and CNR (TSX) have 0 trades.
SELECT s.ticker,
       COUNT(t.transaction_id)                                         AS trades,
       COALESCE(SUM(CASE WHEN t.transaction_type = 'buy'  THEN 1 END), 0) AS buys,
       COALESCE(SUM(CASE WHEN t.transaction_type = 'sell' THEN 1 END), 0) AS sells,
       COALESCE(SUM(t.quantity), 0)                                    AS shares_traded,
       ROUND(COALESCE(SUM(t.quantity * t.price), 0), 2)                AS dollar_volume,
       COUNT(DISTINCT t.portfolio_id)                                  AS portfolios
FROM stock AS s
LEFT JOIN `transaction` AS t ON t.ticker = s.ticker
GROUP BY s.ticker
ORDER BY trades DESC;

-- -----------------------------------------------------
-- Q5: Cash balance consistency check (C.7.9)
-- -----------------------------------------------------
-- Compare each user's stored cash_balance with the balance rebuilt from the
-- ledger: 100000.00 - SUM(buy totals) + SUM(sell totals) across all of their
-- portfolios, rounding each trade to 2 decimals like trg_transaction_after_insert.
-- Return only the users where the two disagree. An empty result means the
-- trigger kept every balance in step with the ledger.
-- Expected: 0 rows.
SELECT u.user_id,
       u.name,
       u.cash_balance,
       100000.00 - COALESCE(l.spent, 0) + COALESCE(l.received, 0) AS rebuilt_balance
FROM `user` AS u
LEFT JOIN (SELECT p.user_id,
                  SUM(CASE WHEN t.transaction_type = 'buy'  THEN ROUND(t.quantity * t.price, 2) END) AS spent,
                  SUM(CASE WHEN t.transaction_type = 'sell' THEN ROUND(t.quantity * t.price, 2) END) AS received
           FROM portfolio AS p
           JOIN `transaction` AS t ON t.portfolio_id = p.portfolio_id
           GROUP BY p.user_id) AS l ON l.user_id = u.user_id
WHERE u.cash_balance <> 100000.00 - COALESCE(l.spent, 0) + COALESCE(l.received, 0);

-- -----------------------------------------------------
-- Q6: Users with no trades
-- -----------------------------------------------------
-- Users with no transactions in any portfolio, including users with no
-- portfolio at all. Show name, email and number of portfolios.
-- Anti-join: NOT EXISTS (portfolio JOIN transaction for that user_id).
-- Expected with the committed seed: 2 rows (Keira Martin, Priya Rossi).
SELECT u.name,
       u.email,
       (SELECT COUNT(*) FROM portfolio AS p WHERE p.user_id = u.user_id) AS portfolios
FROM `user` AS u
WHERE NOT EXISTS (SELECT 1
                  FROM portfolio AS p
                  JOIN `transaction` AS t ON t.portfolio_id = p.portfolio_id
                  WHERE p.user_id = u.user_id)
ORDER BY u.name;

-- -----------------------------------------------------
-- Q7: Each user's largest holding
-- -----------------------------------------------------
-- For each user, the single stock with the highest market value, summing
-- shares of the same ticker across their portfolios: name, ticker, shares,
-- market value.
-- Top-1 per group: ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY
-- market value DESC) in a subquery/CTE, keep row number 1.

-- -----------------------------------------------------
-- Q8: Holdings never go negative (C.7.8)
-- -----------------------------------------------------
-- Replaces the old average_price check (holds and average_price are gone).
-- Running share count per (portfolio_id, ticker) over time:
-- SUM(+quantity for buys, -quantity for sells) OVER (PARTITION BY
-- portfolio_id, ticker ORDER BY executed_at, transaction_id).
-- Return any row where the running count drops below 0. An empty result
-- means no portfolio ever sold shares it didn't hold.
-- Expected: 0 rows.
SELECT *
FROM (SELECT t.transaction_id,
             t.portfolio_id,
             t.ticker,
             t.executed_at,
             SUM(CASE WHEN t.transaction_type = 'buy' THEN t.quantity ELSE -t.quantity END)
               OVER (PARTITION BY t.portfolio_id, t.ticker
                     ORDER BY t.executed_at, t.transaction_id) AS running_shares
      FROM `transaction` AS t) AS r
WHERE r.running_shares < 0;

-- -----------------------------------------------------
-- Q9: Cash flow per user
-- -----------------------------------------------------
-- For each user: total spent on buys, total received from sells, net cash
-- flow (received - spent) and current cash_balance.
-- Conditional aggregation: SUM(CASE WHEN transaction_type = 'buy' ...).
-- Joins: user LEFT JOIN portfolio LEFT JOIN transaction, so users with no
-- trades show zeros. Order by net cash flow.

-- -----------------------------------------------------
-- Q10: Daily movers
-- -----------------------------------------------------
-- For the latest price_date: each stock's previous close, latest close,
-- change and percent change ((close - previous close) / previous close * 100).
-- Previous close: LAG(closing_price) OVER (PARTITION BY ticker ORDER BY
-- price_date) on stock_price_history, then keep the latest date.
-- Order by percent change descending (biggest gainers first, losers last).
-- Expected: 14 rows, one per stock.
SELECT d.ticker,
       d.previous_close,
       d.closing_price                                                   AS latest_close,
       d.closing_price - d.previous_close                                AS `change`,
       ROUND((d.closing_price - d.previous_close) / d.previous_close * 100, 2) AS percent_change
FROM (SELECT h.ticker,
             h.price_date,
             h.closing_price,
             LAG(h.closing_price) OVER (PARTITION BY h.ticker ORDER BY h.price_date) AS previous_close
      FROM stock_price_history AS h) AS d
JOIN v_latest_price AS lp ON lp.ticker = d.ticker AND lp.price_date = d.price_date
ORDER BY percent_change DESC;

-- -----------------------------------------------------
-- Q11: Most active traders
-- -----------------------------------------------------
-- Users with more than N trades across all portfolios (pick N from the seed
-- data): name, trade count, total shares traded, number of distinct stocks
-- traded and number of portfolios used.
-- Joins: user JOIN portfolio JOIN transaction, GROUP BY user,
-- HAVING COUNT(*) > N. Order by trade count descending.
-- N = 220 (the average is about 100 trades per user). Expected with the
-- committed seed: 15 users, from Jonas Haddad (287 trades) down.
SELECT u.name,
       COUNT(*)                       AS trades,
       SUM(t.quantity)                AS shares_traded,
       COUNT(DISTINCT t.ticker)       AS stocks,
       COUNT(DISTINCT t.portfolio_id) AS portfolios_used
FROM `user` AS u
JOIN portfolio     AS p ON p.user_id      = u.user_id
JOIN `transaction` AS t ON t.portfolio_id = p.portfolio_id
GROUP BY u.user_id, u.name
HAVING COUNT(*) > 220
ORDER BY trades DESC;

-- -----------------------------------------------------
-- Q12: Stocks nobody holds
-- -----------------------------------------------------
-- Stocks where no portfolio currently holds shares (net shares > 0):
-- ticker, company_name, exchange_code. Includes stocks that were traded
-- and then fully sold.
-- Anti-join: NOT EXISTS (holdings with that ticker). Counterpart to Q6.

-- -----------------------------------------------------
-- Q13: Exposure by exchange per user
-- -----------------------------------------------------
-- For each user and exchange: exchange_name, currency, market value held on
-- that exchange and its share of the user's total market value (percent).
-- Joins: holdings JOIN portfolio JOIN stock JOIN exchange JOIN latest price,
-- GROUP BY user, exchange. The total per user can come from
-- SUM(...) OVER (PARTITION BY user_id). Percentages mix USD and CAD
-- (see Currency above). Order by user, then exchange.

-- -----------------------------------------------------
-- Q14: Trading volume over time
-- -----------------------------------------------------
-- Per month: number of trades, buys vs. sells, total shares traded and total
-- dollar volume (SUM(quantity * price)).
-- GROUP BY DATE_FORMAT(executed_at, '%Y-%m'), order by month.

-- -----------------------------------------------------
-- Q15: Biggest losers
-- -----------------------------------------------------
-- Counterpart to the Q3 leaderboard, ranked by return instead of size.
-- Uses the Q16 return rate for every user. Keep only users whose return is
-- below 0 and rank with RANK() OVER (ORDER BY return rate ASC), so the
-- worst performer is rank 1.

-- -----------------------------------------------------
-- Q16: Return rate for one user across all portfolios
-- -----------------------------------------------------
-- Simple return for a single user (e.g. user_id = 1):
--   net worth   = cash_balance + market value of all holdings
--   return rate = (net worth - 100000.00) / 100000.00 * 100
-- Counts both realized gains (already in cash_balance) and unrealized gains.
-- Joins: user LEFT JOIN (holdings across portfolios JOIN latest price),
-- filtered on user_id. Returns one row.

-- -----------------------------------------------------
-- Q17: Return rate for one portfolio
-- -----------------------------------------------------
-- Cash is stored per user, not per portfolio, so this uses the ledger
-- instead of a starting balance. For one portfolio (e.g. portfolio_id = 1):
--   invested    = SUM(buy quantity * price)
--   proceeds    = SUM(sell quantity * price)
--   profit      = proceeds + market value of current holdings - invested
--   return rate = profit / invested * 100
-- Show portfolio_name, owner, invested, proceeds, market value, profit and
-- return rate. Joins: portfolio JOIN user JOIN transaction, plus holdings
-- JOIN latest price, filtered on portfolio_id.

-- -----------------------------------------------------
-- Index check: the C.7.8 sell check uses idx_transaction_portfolio_ticker
-- -----------------------------------------------------
-- trg_transaction_before_insert sums a portfolio's trades in one ticker before
-- every sell. This is the same lookup. Expected: type = ref, key =
-- idx_transaction_portfolio_ticker, ref = const,const (both columns used).
EXPLAIN SELECT COALESCE(SUM(IF(t.transaction_type = 'buy', t.quantity, -t.quantity)), 0)
FROM `transaction` AS t
WHERE t.portfolio_id = 1
  AND t.ticker = 'AAPL';
