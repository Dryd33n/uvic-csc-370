-- Goal B: lossless join check (goes with docs/lossless-join.md)
-- For each decomposition: build the original relation R, project it into the
-- decomposed tables, join them back and compare with R.
-- Runs in its own database so it doesn't touch stock_trading.
-- Needs MySQL 8.0.31+ for EXCEPT.

DROP DATABASE IF EXISTS lossless_check;
CREATE DATABASE lossless_check;
USE lossless_check;

-- -----------------------------------------------------
-- 1. stock / exchange
-- -----------------------------------------------------
CREATE TABLE r_stock (
    ticker        VARCHAR(10),
    company_name  VARCHAR(100),
    exchange_code VARCHAR(20),
    exchange_name VARCHAR(100),
    country       VARCHAR(50)
);
INSERT INTO r_stock VALUES
    ('AAPL', 'Apple Inc.',            'NASDAQ', 'Nasdaq Stock Market',     'USA'),
    ('MSFT', 'Microsoft Corporation', 'NASDAQ', 'Nasdaq Stock Market',     'USA'),
    ('JPM',  'JPMorgan Chase & Co.',  'NYSE',   'New York Stock Exchange', 'USA'),
    ('KO',   'The Coca-Cola Company', 'NYSE',   'New York Stock Exchange', 'USA'),
    ('RY',   'Royal Bank of Canada',  'TSX',    'Toronto Stock Exchange',  'Canada');

CREATE TABLE stock    AS SELECT DISTINCT ticker, company_name, exchange_code FROM r_stock;
CREATE TABLE exchange AS SELECT DISTINCT exchange_code, exchange_name, country FROM r_stock;

-- -----------------------------------------------------
-- 2. orders / trade
--   order 101 is filled in two pieces (partial fill)
-- -----------------------------------------------------
CREATE TABLE r_trade (
    trade_id     INT,
    order_id     INT,
    portfolio_id INT,
    ticker       VARCHAR(10),
    side         ENUM('buy', 'sell'),
    limit_price  DECIMAL(12, 4),
    fill_qty     INT,
    fill_price   DECIMAL(12, 4)
);
INSERT INTO r_trade VALUES
    (1, 101, 1, 'AAPL', 'buy',  220.0000, 10, 219.8000),
    (2, 101, 1, 'AAPL', 'buy',  220.0000, 15, 219.9500),
    (3, 102, 2, 'AAPL', 'buy',  NULL,      5, 220.5100),  -- market order
    (4, 103, 2, 'KO',   'sell', 66.5000,  20, 66.5000),
    (5, 104, 3, 'MSFT', 'buy',  NULL,      3, 483.8200);

CREATE TABLE orders AS SELECT DISTINCT order_id, portfolio_id, ticker, side, limit_price FROM r_trade;
CREATE TABLE trade  AS SELECT DISTINCT trade_id, order_id, fill_qty, fill_price FROM r_trade;

-- -----------------------------------------------------
-- 3. watchlist / watchlist_item
-- -----------------------------------------------------
CREATE TABLE r_watchlist (
    watchlist_id   INT,
    user_id        INT,
    name           VARCHAR(50),
    ticker         VARCHAR(10),
    added_at       DATETIME
);
INSERT INTO r_watchlist VALUES
    (1, 1, 'tech',      'AAPL', '2026-09-20 10:15:00'),
    (1, 1, 'tech',      'MSFT', '2026-09-21 09:30:00'),
    (2, 1, 'dividends', 'KO',   '2026-09-22 14:00:00'),
    (3, 4, 'banks',     'JPM',  '2026-09-25 11:45:00'),
    (3, 4, 'banks',     'RY',   '2026-09-25 11:46:00');

CREATE TABLE watchlist      AS SELECT DISTINCT watchlist_id, user_id, name FROM r_watchlist;
CREATE TABLE watchlist_item AS SELECT DISTINCT watchlist_id, ticker, added_at FROM r_watchlist;

-- -----------------------------------------------------
-- 4. bad split on purpose: orders/trade joined on ticker
-- -----------------------------------------------------
CREATE TABLE r1 AS SELECT DISTINCT trade_id, ticker, fill_qty, fill_price FROM r_trade;
CREATE TABLE r2 AS SELECT DISTINCT order_id, portfolio_id, ticker, side, limit_price FROM r_trade;

-- -----------------------------------------------------
-- Join back and compare
--   missing = rows of R not in the join
--   extra   = rows of the join not in R (spurious tuples)
-- -----------------------------------------------------
CREATE VIEW j_stock AS
    SELECT s.ticker, s.company_name, s.exchange_code, e.exchange_name, e.country
    FROM stock s JOIN exchange e ON s.exchange_code = e.exchange_code;

CREATE VIEW j_trade AS
    SELECT t.trade_id, t.order_id, o.portfolio_id, o.ticker, o.side, o.limit_price, t.fill_qty, t.fill_price
    FROM orders o JOIN trade t ON o.order_id = t.order_id;

CREATE VIEW j_watchlist AS
    SELECT w.watchlist_id, w.user_id, w.name, i.ticker, i.added_at
    FROM watchlist w JOIN watchlist_item i ON w.watchlist_id = i.watchlist_id;

CREATE VIEW j_bad AS
    SELECT r1.trade_id, r2.order_id, r2.portfolio_id, r2.ticker, r2.side, r2.limit_price, r1.fill_qty, r1.fill_price
    FROM r1 JOIN r2 ON r1.ticker = r2.ticker;

SELECT d.decomposition, d.original_rows, d.joined_rows, d.missing, d.extra,
       IF(d.missing = 0 AND d.extra = 0 AND d.original_rows = d.joined_rows, 'PASS', 'FAIL') AS result
FROM (
    SELECT 'stock / exchange' AS decomposition,
           (SELECT COUNT(*) FROM r_stock) AS original_rows,
           (SELECT COUNT(*) FROM j_stock) AS joined_rows,
           (SELECT COUNT(*) FROM (SELECT * FROM r_stock EXCEPT SELECT * FROM j_stock) x) AS missing,
           (SELECT COUNT(*) FROM (SELECT * FROM j_stock EXCEPT SELECT * FROM r_stock) x) AS extra
    UNION ALL
    SELECT 'orders / trade',
           (SELECT COUNT(*) FROM r_trade),
           (SELECT COUNT(*) FROM j_trade),
           (SELECT COUNT(*) FROM (SELECT * FROM r_trade EXCEPT SELECT * FROM j_trade) x),
           (SELECT COUNT(*) FROM (SELECT * FROM j_trade EXCEPT SELECT * FROM r_trade) x)
    UNION ALL
    SELECT 'watchlist / watchlist_item',
           (SELECT COUNT(*) FROM r_watchlist),
           (SELECT COUNT(*) FROM j_watchlist),
           (SELECT COUNT(*) FROM (SELECT * FROM r_watchlist EXCEPT SELECT * FROM j_watchlist) x),
           (SELECT COUNT(*) FROM (SELECT * FROM j_watchlist EXCEPT SELECT * FROM r_watchlist) x)
    UNION ALL
    SELECT 'bad split on ticker (should FAIL)',
           (SELECT COUNT(*) FROM r_trade),
           (SELECT COUNT(*) FROM j_bad),
           (SELECT COUNT(*) FROM (SELECT * FROM r_trade EXCEPT SELECT * FROM j_bad) x),
           (SELECT COUNT(*) FROM (SELECT * FROM j_bad EXCEPT SELECT * FROM r_trade) x)
) d;

-- The spurious rows from the bad split: AAPL trades paired with the wrong order
SELECT * FROM j_bad EXCEPT SELECT * FROM r_trade ORDER BY trade_id, order_id;

-- -----------------------------------------------------
-- Open orders (see docs/lossless-join.md, section 2)
--   An unfilled limit order has no trades, so it's in orders but not in the
--   join. R had no way to store it anyway (one row per trade), so this isn't
--   data the decomposition lost.
-- -----------------------------------------------------
INSERT INTO orders VALUES (105, 3, 'JPM', 'buy', 250.0000);

SELECT o.order_id, o.ticker, o.limit_price, COUNT(t.trade_id) AS trades
FROM orders o LEFT JOIN trade t ON o.order_id = t.order_id
GROUP BY o.order_id, o.ticker, o.limit_price
ORDER BY o.order_id;

DROP DATABASE lossless_check;
