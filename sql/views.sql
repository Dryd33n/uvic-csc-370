-- Views for the stock_trading schema
--   Run after ddl.sql and seed.sql (Docker and CI load it third).
--   There is no holdings table: positions are derived from the transaction
--   ledger, so they can never disagree with it. These views name the shared
--   definitions that sql/queries.sql builds on.
--   CREATE OR REPLACE, so the file can be re-run at any time.

USE stock_trading;

-- -----------------------------------------------------
-- v_latest_price: each ticker's closing price on its most recent price_date
--   One row per ticker that has price history.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW `v_latest_price` AS
SELECT h.ticker,
       h.price_date,
       h.closing_price AS latest_price
FROM stock_price_history AS h
JOIN (SELECT ticker, MAX(price_date) AS price_date
      FROM stock_price_history
      GROUP BY ticker) AS m
  ON m.ticker = h.ticker AND m.price_date = h.price_date;

-- -----------------------------------------------------
-- v_holdings: shares currently held per (portfolio_id, ticker)
--   shares     = SUM(buy quantity) - SUM(sell quantity); only rows > 0
--   cost_basis = average buy price, SUM(buy quantity * price) / SUM(buy quantity).
--                Approximate if a position was fully sold and bought again.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW `v_holdings` AS
SELECT t.portfolio_id,
       t.ticker,
       SUM(CASE WHEN t.transaction_type = 'buy' THEN t.quantity ELSE -t.quantity END) AS shares,
       SUM(CASE WHEN t.transaction_type = 'buy' THEN t.quantity * t.price END)
         / SUM(CASE WHEN t.transaction_type = 'buy' THEN t.quantity END)         AS cost_basis
FROM `transaction` AS t
GROUP BY t.portfolio_id, t.ticker
HAVING shares > 0;

-- -----------------------------------------------------
-- v_position_value: each holding valued at the latest price
--   market_value    = shares * latest_price
--   unrealized_gain = (latest_price - cost_basis) * shares
--   Carries user_id so per-user totals need no extra join.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW `v_position_value` AS
SELECT p.user_id,
       h.portfolio_id,
       h.ticker,
       h.shares,
       h.cost_basis,
       lp.latest_price,
       h.shares * lp.latest_price                     AS market_value,
       (lp.latest_price - h.cost_basis) * h.shares    AS unrealized_gain
FROM v_holdings     AS h
JOIN portfolio      AS p  ON p.portfolio_id = h.portfolio_id
JOIN v_latest_price AS lp ON lp.ticker      = h.ticker;
