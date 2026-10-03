USE stock_trading;

-- -----------------------------------------------------
-- 1. Alice's current holdings, valued at the latest closing price
--    Expected: 4 rows (GOOGL, MSFT, NVDA, AAPL); MSFT is up, NVDA and AAPL are down
-- -----------------------------------------------------
SELECT h.ticker,
       s.company_name,
       h.quantity,
       h.average_price,
       s.closing_price,
       ROUND(h.quantity * s.closing_price, 2)                     AS market_value,
       ROUND(h.quantity * (s.closing_price - h.average_price), 2) AS unrealized_gain
FROM `user` AS u
JOIN holds  AS h ON h.user_id = u.user_id
JOIN stock  AS s ON s.ticker  = h.ticker
WHERE u.email = 'alice@example.com'
ORDER BY market_value DESC;

-- -----------------------------------------------------
-- 2. Chika's trade history, newest first
--    Expected: 18 rows, starting with the DIS buy on 2026-09-28
-- -----------------------------------------------------
SELECT t.transaction_id,
       t.`time`,
       t.transaction_type,
       t.ticker,
       t.quantity,
       t.price,
       t.quantity * t.price AS total
FROM `user` AS u
JOIN `transaction` AS t ON t.user_id = u.user_id
WHERE u.email = 'chika@example.com'
ORDER BY t.`time` DESC;

-- -----------------------------------------------------
-- 3. Leaderboard: every user ranked by unrealized gain on open positions
--    LEFT JOIN keeps users with no holdings (Isla) at 0.
--    Expected: 9 rows; Alice first (+281.64), Chika last (-508.63)
-- -----------------------------------------------------
SELECT RANK() OVER (ORDER BY COALESCE(SUM(h.quantity * (s.closing_price - h.average_price)), 0) DESC) AS place,
       u.name,
       COUNT(h.ticker) AS positions,
       ROUND(COALESCE(SUM(h.quantity * s.closing_price), 0), 2) AS market_value,
       ROUND(COALESCE(SUM(h.quantity * (s.closing_price - h.average_price)), 0), 2) AS unrealized_gain
FROM `user` AS u
LEFT JOIN holds AS h ON h.user_id = u.user_id
LEFT JOIN stock AS s ON s.ticker  = h.ticker
GROUP BY u.user_id, u.name
ORDER BY place, u.name;

-- -----------------------------------------------------
-- 4. Trading activity per stock, including stocks nobody traded
--    Expected: 14 rows; the TSX stocks (CNR, ATD) have 0 trades
-- -----------------------------------------------------
SELECT s.ticker,
       s.exchange,
       COUNT(t.transaction_id) AS trades,
       COALESCE(SUM(CASE WHEN t.transaction_type = 'buy'  THEN t.quantity END), 0) AS shares_bought,
       COALESCE(SUM(CASE WHEN t.transaction_type = 'sell' THEN t.quantity END), 0) AS shares_sold
FROM stock AS s
LEFT JOIN `transaction` AS t ON t.ticker = s.ticker
GROUP BY s.ticker, s.exchange
ORDER BY trades DESC, s.ticker;

-- -----------------------------------------------------
-- 5. holds is derived data: compare each stored position with the
--    shares bought minus sold in `transaction`
--    Expected: 0 rows (the stored holds match the trade history)
-- -----------------------------------------------------
WITH net AS (
    SELECT user_id,
           ticker,
           SUM(CASE WHEN transaction_type = 'buy' THEN quantity ELSE -quantity END) AS net_quantity
    FROM `transaction`
    GROUP BY user_id, ticker
)
SELECT h.user_id, h.ticker, h.quantity AS in_holds, n.net_quantity AS from_trades
FROM holds AS h
LEFT JOIN net AS n ON n.user_id = h.user_id AND n.ticker = h.ticker
WHERE n.net_quantity IS NULL OR n.net_quantity <> h.quantity
UNION ALL
SELECT n.user_id, n.ticker, NULL, n.net_quantity
FROM net AS n
LEFT JOIN holds AS h ON h.user_id = n.user_id AND h.ticker = n.ticker
WHERE n.net_quantity > 0 AND h.user_id IS NULL;

-- -----------------------------------------------------
-- 6. Users who have never traded
--    Expected: 1 row (Isla MacDonald)
-- -----------------------------------------------------
SELECT u.user_id, u.name, u.email
FROM `user` AS u
WHERE NOT EXISTS (SELECT 1 FROM `transaction` AS t WHERE t.user_id = u.user_id);
