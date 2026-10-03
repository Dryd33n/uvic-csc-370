USE stock_trading;

START TRANSACTION;

-- -----------------------------------------------------
-- user
-- -----------------------------------------------------
-- 1. Duplicate user_id (Alice is user 1)            -> 1062 PRIMARY KEY
INSERT INTO `user` (`user_id`, `name`, `email`) VALUES (1, 'Duplicate Id', 'dup.id@example.com');

-- 2. Duplicate email                                 -> 1062 UNIQUE
INSERT INTO `user` (`user_id`, `name`, `email`) VALUES (10, 'Alice Clone', 'alice@example.com');

-- 3. Missing email                                   -> 1048 NOT NULL
INSERT INTO `user` (`user_id`, `name`, `email`) VALUES (11, 'No Email', NULL);

-- -----------------------------------------------------
-- stock
-- -----------------------------------------------------
-- 4. Duplicate ticker                                -> 1062 PRIMARY KEY
INSERT INTO `stock` (`ticker`, `company_name`, `opening_price`, `closing_price`, `exchange`)
VALUES ('AAPL', 'Apple Again Inc.', 100.00, 101.00, 'NASDAQ');

-- -----------------------------------------------------
-- transaction
-- -----------------------------------------------------
-- 5. Trade on a ticker that does not exist           -> 1452 FOREIGN KEY
INSERT INTO `transaction` (`transaction_id`, `user_id`, `ticker`, `transaction_type`, `quantity`, `price`, `time`)
VALUES (83, 1, 'FAKE', 'buy', 10, 50.00, '2026-09-28 10:00:00');

-- 6. Trade by a user who does not exist              -> 1452 FOREIGN KEY
INSERT INTO `transaction` (`transaction_id`, `user_id`, `ticker`, `transaction_type`, `quantity`, `price`, `time`)
VALUES (84, 99, 'AAPL', 'buy', 10, 220.00, '2026-09-28 10:00:00');

-- 7. Negative quantity                               -> 3819 CHECK
INSERT INTO `transaction` (`transaction_id`, `user_id`, `ticker`, `transaction_type`, `quantity`, `price`, `time`)
VALUES (85, 1, 'AAPL', 'buy', -5, 220.00, '2026-09-28 10:00:00');

-- 8. Price of zero                                   -> 3819 CHECK
INSERT INTO `transaction` (`transaction_id`, `user_id`, `ticker`, `transaction_type`, `quantity`, `price`, `time`)
VALUES (86, 1, 'AAPL', 'buy', 5, 0.00, '2026-09-28 10:00:00');

-- -----------------------------------------------------
-- holds
-- -----------------------------------------------------
-- 9. Second row for the same user and stock          -> 1062 PRIMARY KEY
INSERT INTO `holds` (`user_id`, `ticker`, `quantity`, `average_price`) VALUES (1, 'NVDA', 5, 170.0000);

-- 10. Holding for a user who does not exist          -> 1452 FOREIGN KEY
INSERT INTO `holds` (`user_id`, `ticker`, `quantity`, `average_price`) VALUES (99, 'AAPL', 5, 220.0000);

-- -----------------------------------------------------
-- Sanity check: if all 10 statements failed, nothing changed.
-- Expected: user 9, stock 14, transaction 82, holds 22
-- -----------------------------------------------------
SELECT 'user' AS tbl, COUNT(*) AS n FROM `user`
UNION ALL SELECT 'stock',       COUNT(*) FROM `stock`
UNION ALL SELECT 'transaction', COUNT(*) FROM `transaction`
UNION ALL SELECT 'holds',       COUNT(*) FROM `holds`;

ROLLBACK;
