-- Goal D: multi-table queries built from relational algebra
--   Each query is written first in relational algebra, then translated to SQL.
--   They use only selection, projection, natural join and arithmetic.
--   Run after ddl.sql and seed.sql. Read-only: nothing is changed.
--
-- Notation (same ASCII style as the comments in ddl.sql)
--   sigma_{c}(R)        selection: rows of R where c is true          -> WHERE
--   pi_{a, b}(R)        projection: keep attributes a, b              -> SELECT list
--   pi_{e -> x}(R)      extended projection: computed attribute x = e -> SELECT e AS x
--   R |><| S            natural join on the attributes R and S share  -> JOIN ... ON
--   tau_{a}(R)          sort by a (presentation only)                 -> ORDER BY
--
-- Shared attributes, so each natural join matches on exactly one column:
--   User |><| Holds        on user_id
--   Holds |><| Stock       on ticker
--   User |><| Transaction  on user_id
--   Transaction |><| Stock on ticker

USE stock_trading;

-- -----------------------------------------------------
-- 1. Portfolio value: Alice's positions at the latest closing price
--
--    pi_{ticker, company_name, quantity, closing_price,
--        quantity * closing_price -> market_value}(
--      sigma_{email = 'alice@example.com'}(User |><| Holds |><| Stock))
--
--    Expected: 4 rows
--      GOOGL  74 x 174.59 = 12919.66
--      MSFT   11 x 483.82 =  5322.02
--      NVDA   25 x 173.06 =  4326.50
--      AAPL    2 x 220.51 =   441.02
-- -----------------------------------------------------
SELECT h.ticker,
       s.company_name,
       h.quantity,
       s.closing_price,
       ROUND(h.quantity * s.closing_price, 2) AS market_value
FROM `user` AS u
JOIN holds  AS h ON h.user_id = u.user_id
JOIN stock  AS s ON s.ticker  = h.ticker
WHERE u.email = 'alice@example.com'
ORDER BY market_value DESC;

-- -----------------------------------------------------
-- 2. Gain/loss per position: Alice's unrealized gain or loss
--
--    pi_{ticker, quantity, average_price, closing_price,
--        quantity * (closing_price - average_price) -> gain_loss}(
--      sigma_{email = 'alice@example.com'}(User |><| Holds |><| Stock))
--
--    Expected: 4 rows
--      MSFT   11 x (483.82 - 451.87)   =  351.45
--      GOOGL  74 x (174.59 - 174.2782) =   23.07
--      AAPL    2 x (220.51 - 231.95)   =  -22.88
--      NVDA   25 x (173.06 - 175.86)   =  -70.00
-- -----------------------------------------------------
SELECT h.ticker,
       h.quantity,
       h.average_price,
       s.closing_price,
       ROUND(h.quantity * (s.closing_price - h.average_price), 2) AS gain_loss
FROM `user` AS u
JOIN holds  AS h ON h.user_id = u.user_id
JOIN stock  AS s ON s.ticker  = h.ticker
WHERE u.email = 'alice@example.com'
ORDER BY gain_loss DESC;

-- -----------------------------------------------------
-- 3. Trade history: Alice's trades with company names, oldest first
--
--    tau_{time}(
--      pi_{transaction_id, time, transaction_type, ticker, company_name,
--          quantity, price, quantity * price -> total}(
--        sigma_{email = 'alice@example.com'}(User |><| Transaction |><| Stock)))
--
--    Expected: 14 rows, from the AAPL buy on 2026-09-01 (id 2)
--    to the AAPL sell on 2026-09-25 (id 75). The GOOGL buys
--    (24 x 172.52, 19 x 170.90, 31 x 177.71) average to 174.2782,
--    the average_price that query 2 reads from holds.
-- -----------------------------------------------------
SELECT t.transaction_id,
       t.`time`,
       t.transaction_type,
       t.ticker,
       s.company_name,
       t.quantity,
       t.price,
       ROUND(t.quantity * t.price, 2) AS total
FROM `user` AS u
JOIN `transaction` AS t ON t.user_id = u.user_id
JOIN stock         AS s ON s.ticker  = t.ticker
WHERE u.email = 'alice@example.com'
ORDER BY t.`time`;
