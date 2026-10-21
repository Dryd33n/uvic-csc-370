-- Constraint tests for sql/ddl.sql
--   Constraint IDs (C.x.y) follow docs/Schemata Overview/schemata.md.
--   Three kinds of test:
--     expect_rejected  the statement must fail with exactly this error code, so a
--                      typo or syntax error can't count as a pass
--     expect_accepted  a boundary value the constraint must still allow
--     expect_true      a default or trigger side effect, checked with a query
--   Run after ddl.sql and seed.sql. The tests insert their own fixture rows (ids
--   9000+), so they don't depend on the seed. Everything runs in one transaction
--   that is rolled back, so the seed data is unchanged. Exits with an error if any
--   test fails, so CI fails too.

USE stock_trading;

-- Expected MySQL error codes
--   1048  ER_BAD_NULL_ERROR              NULL in a NOT NULL column
--   1062  ER_DUP_ENTRY                   duplicate primary key or UNIQUE value
--   1265  WARN_DATA_TRUNCATED            value not in the ENUM (an error in strict mode)
--   1451  ER_ROW_IS_REFERENCED_2         parent row is still referenced by a child row
--   1452  ER_NO_REFERENCED_ROW_2         foreign key points to a missing parent row
--   1644  ER_SIGNAL_EXCEPTION            a trigger rejected the row (SIGNAL SQLSTATE '45000')
--   3819  ER_CHECK_CONSTRAINT_VIOLATED   CHECK constraint is false

-- -----------------------------------------------------
-- Test harness
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS `expect_rejected`;
DROP PROCEDURE IF EXISTS `expect_accepted`;
DROP PROCEDURE IF EXISTS `expect_true`;
DROP PROCEDURE IF EXISTS `assert_all_passed`;

-- MEMORY tables are not transactional, so results survive the final ROLLBACK
DROP TEMPORARY TABLE IF EXISTS `constraint_test_results`;
CREATE TEMPORARY TABLE `constraint_test_results` (
    `test`          VARCHAR(120) NOT NULL,
    `expected_code` INT          NULL,      -- NULL means the statement must be accepted
    `actual_code`   INT          NULL,      -- NULL means the statement was accepted
    `passed`        BOOLEAN      NOT NULL,
    `message`       VARCHAR(512) NULL
) ENGINE = MEMORY;

DELIMITER //

-- Runs `stmt` and records whether it failed with `expected_code` (NULL = must succeed)
CREATE PROCEDURE `expect_rejected`(IN test_name VARCHAR(120), IN expected_code INT, IN stmt TEXT)
BEGIN
    DECLARE actual_code INT DEFAULT NULL;
    DECLARE message VARCHAR(512) DEFAULT 'accepted';

    BEGIN
        -- SQLWARNING too: strict mode rejects a bad ENUM value with error 1265,
        -- but its SQLSTATE (01000) is warning-class, so SQLEXCEPTION misses it
        DECLARE EXIT HANDLER FOR SQLEXCEPTION, SQLWARNING
            GET DIAGNOSTICS CONDITION 1 actual_code = MYSQL_ERRNO, message = MESSAGE_TEXT;

        SET @stmt = stmt;
        PREPARE test_stmt FROM @stmt;
        EXECUTE test_stmt;
        DEALLOCATE PREPARE test_stmt;
    END;

    INSERT INTO `constraint_test_results`
    VALUES (test_name, expected_code, actual_code, actual_code <=> expected_code, message);
END //

CREATE PROCEDURE `expect_accepted`(IN test_name VARCHAR(120), IN stmt TEXT)
BEGIN
    CALL expect_rejected(test_name, NULL, stmt);
END //

-- Evaluates the boolean expression `cond` (usually a subquery)
CREATE PROCEDURE `expect_true`(IN test_name VARCHAR(120), IN cond TEXT)
BEGIN
    SET @ok = NULL;
    SET @stmt = CONCAT('SELECT (', cond, ') INTO @ok');
    PREPARE test_stmt FROM @stmt;
    EXECUTE test_stmt;
    DEALLOCATE PREPARE test_stmt;

    INSERT INTO `constraint_test_results`
    VALUES (test_name, NULL, NULL, COALESCE(@ok = 1, FALSE),
            IF(COALESCE(@ok = 1, FALSE), 'true', LEFT(CONCAT('false: ', cond), 512)));
END //

-- Raises an error if any test failed, so the mysql client exits non-zero
CREATE PROCEDURE `assert_all_passed`()
BEGIN
    DECLARE failures INT;
    SELECT COUNT(*) INTO failures FROM `constraint_test_results` WHERE NOT `passed`;
    IF failures > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Constraint tests failed: see the results table above';
    END IF;
END //

DELIMITER ;

-- Outside strict mode, MySQL stores a bad ENUM value as '' with only a warning,
-- so the ENUM tests below would pass without rejecting anything
INSERT INTO `constraint_test_results`
VALUES ('server: sql_mode is strict', NULL, NULL,
        @@SESSION.sql_mode LIKE '%STRICT_TRANS_TABLES%' OR @@SESSION.sql_mode LIKE '%STRICT_ALL_TABLES%',
        @@SESSION.sql_mode);

-- Row counts before the tests, compared after the rollback
SET @counts_before = (SELECT CONCAT_WS('/',
    (SELECT COUNT(*) FROM `exchange`), (SELECT COUNT(*) FROM `stock`),
    (SELECT COUNT(*) FROM `stock_price_history`), (SELECT COUNT(*) FROM `user`),
    (SELECT COUNT(*) FROM `portfolio`), (SELECT COUNT(*) FROM `watchlist`),
    (SELECT COUNT(*) FROM `transaction`), (SELECT COUNT(*) FROM `limit_order`)));

START TRANSACTION;

-- -----------------------------------------------------
-- Fixtures (plain statements: if one fails, the script stops)
--   user 9001: cash 1000.00, portfolios 9001 'Main' and 9002 'Second'
--   user 9002: default cash, portfolio 9003, no trades (used by the cascade tests)
--   stock TST traded; TST2 never traded (used by the cascade tests)
--   one buy: 5 TST @ 100.00 in portfolio 9001, leaving user 9001 with 500.00
-- -----------------------------------------------------
INSERT INTO `exchange` VALUES ('TESTX', 'Test Exchange', 'Canada', 'CAD');
INSERT INTO `stock` VALUES ('TST', 'Test Corp', 'Technology', 'TESTX'),
                           ('TST2', 'Test Corp Two', 'Energy', 'TESTX');
INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-30', 100.00, 101.00, 102.00, 99.00, 1000),
                                         ('TST2', '2026-09-30', 50.00, 51.00, 52.00, 49.00, 1000);
INSERT INTO `user` (`user_id`, `name`, `email`, `cash_balance`)
VALUES (9001, 'Test User', 'test.user@example.com', 1000.00);
INSERT INTO `user` (`user_id`, `name`, `email`) VALUES (9002, 'Idle User', 'idle.user@example.com');
INSERT INTO `portfolio` (`portfolio_id`, `user_id`, `portfolio_name`)
VALUES (9001, 9001, 'Main'), (9002, 9001, 'Second'), (9003, 9002, 'Only');
INSERT INTO `watchlist` (`user_id`, `ticker`, `target_price`) VALUES (9001, 'TST2', 55.00), (9002, 'TST', 90.00);
INSERT INTO `limit_order` (`order_id`, `portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`)
VALUES (9001, 9003, 'TST', 'buy', 95.00, 1), (9002, 9002, 'TST2', 'buy', 45.00, 1);
INSERT INTO `transaction` (`transaction_id`, `portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`, `executed_at`)
VALUES (90001, 9001, 'TST', 'buy', 5, 100.00, '2026-09-30 10:00:00');

-- -----------------------------------------------------
-- user
-- -----------------------------------------------------
-- C.1.1: reusing an existing user_id
CALL expect_rejected('C.1.1 user: duplicate user_id', 1062,
    "INSERT INTO `user` (`user_id`, `name`, `email`) VALUES (9001, 'Dup', 'dup@example.com')");
-- C.1.2: same email in a different case (the collation is case-insensitive)
CALL expect_rejected('C.1.2 user: duplicate email, different case', 1062,
    "INSERT INTO `user` (`name`, `email`) VALUES ('Dup', 'TEST.USER@example.com')");
-- C.1.3: missing name
CALL expect_rejected('C.1.3 user: NULL name', 1048,
    "INSERT INTO `user` (`name`, `email`) VALUES (NULL, 'noname@example.com')");
-- C.1.3: missing email
CALL expect_rejected('C.1.3 user: NULL email', 1048,
    "INSERT INTO `user` (`name`, `email`) VALUES ('No Email', NULL)");
-- C.1.4: no @
CALL expect_rejected('C.1.4 user: email without @', 3819,
    "INSERT INTO `user` (`name`, `email`) VALUES ('Bad', 'bad.example.com')");
-- C.1.4: no dot in the domain
CALL expect_rejected('C.1.4 user: email without a domain', 3819,
    "INSERT INTO `user` (`name`, `email`) VALUES ('Bad', 'bad@example')");
-- C.1.5: one cent below zero
CALL expect_rejected('C.1.5 user: cash_balance = -0.01', 3819,
    "INSERT INTO `user` (`name`, `email`, `cash_balance`) VALUES ('Broke', 'broke@example.com', -0.01)");
-- C.1.5 boundary: exactly zero is allowed
CALL expect_accepted('C.1.5 user: cash_balance = 0.00 allowed',
    "INSERT INTO `user` (`user_id`, `name`, `email`, `cash_balance`) VALUES (9003, 'Zero', 'zero@example.com', 0.00)");
-- C.1.6: a user inserted without cash_balance gets the starting amount
CALL expect_true('C.1.6 user: cash_balance defaults to 100000.00',
    "SELECT `cash_balance` = 100000.00 FROM `user` WHERE `user_id` = 9002");

-- -----------------------------------------------------
-- portfolio
-- -----------------------------------------------------
-- C.2.2: owner doesn't exist
CALL expect_rejected('C.2.2 portfolio: unknown user_id', 1452,
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (999999, 'Ghost')");
-- C.2.2: no owner
CALL expect_rejected('C.2.2 portfolio: NULL user_id', 1048,
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (NULL, 'Ghost')");
-- C.2.4: same user, same name
CALL expect_rejected('C.2.4 portfolio: duplicate name for one user', 1062,
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (9001, 'Main')");
-- C.2.4 boundary: a different user may reuse the name
CALL expect_accepted('C.2.4 portfolio: same name, different user allowed',
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (9002, 'Main')");
-- C.2.5: empty string
CALL expect_rejected('C.2.5 portfolio: empty name', 3819,
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (9001, '')");
-- C.2.5: NULL name
CALL expect_rejected('C.2.5 portfolio: NULL name', 1048,
    "INSERT INTO `portfolio` (`user_id`, `portfolio_name`) VALUES (9001, NULL)");
-- C.2.6: fixture portfolios were inserted without created_at
CALL expect_true('C.2.6 portfolio: created_at defaults to now',
    "SELECT `created_at` IS NOT NULL FROM `portfolio` WHERE `portfolio_id` = 9001");

-- -----------------------------------------------------
-- exchange
-- -----------------------------------------------------
-- C.3.1: reusing an exchange code
CALL expect_rejected('C.3.1 exchange: duplicate exchange_code', 1062,
    "INSERT INTO `exchange` VALUES ('TESTX', 'Dup', 'Canada', 'CAD')");
-- C.3.2: missing country
CALL expect_rejected('C.3.2 exchange: NULL country', 1048,
    "INSERT INTO `exchange` VALUES ('TESTY', 'Test Y', NULL, 'CAD')");
-- C.3.3: too short
CALL expect_rejected('C.3.3 exchange: 2-letter currency', 3819,
    "INSERT INTO `exchange` VALUES ('TESTY', 'Test Y', 'Canada', 'CA')");
-- C.3.3: too long (the column allows 10 characters, the CHECK only 3)
CALL expect_rejected('C.3.3 exchange: 4-letter currency', 3819,
    "INSERT INTO `exchange` VALUES ('TESTY', 'Test Y', 'Canada', 'CADX')");
-- C.3.4: mixed case would pass a plain = UPPER() check under the case-insensitive collation
CALL expect_rejected('C.3.4 exchange: mixed-case exchange_code', 3819,
    "INSERT INTO `exchange` VALUES ('Testy', 'Test Y', 'Canada', 'CAD')");

-- -----------------------------------------------------
-- stock
-- -----------------------------------------------------
-- C.4.1: reusing a ticker
CALL expect_rejected('C.4.1 stock: duplicate ticker', 1062,
    "INSERT INTO `stock` VALUES ('TST', 'Dup', 'Energy', 'TESTX')");
-- C.4.2: exchange doesn't exist
CALL expect_rejected('C.4.2 stock: unknown exchange_code', 1452,
    "INSERT INTO `stock` VALUES ('TST3', 'Test Three', 'Energy', 'NOPE')");
-- C.4.2: no exchange
CALL expect_rejected('C.4.2 stock: NULL exchange_code', 1048,
    "INSERT INTO `stock` VALUES ('TST3', 'Test Three', 'Energy', NULL)");
-- C.4.4: one lowercase letter (same collation edge case as C.3.4)
CALL expect_rejected('C.4.4 stock: mixed-case ticker', 3819,
    "INSERT INTO `stock` VALUES ('TSt3', 'Test Three', 'Energy', 'TESTX')");
-- C.4.5: missing company name
CALL expect_rejected('C.4.5 stock: NULL company_name', 1048,
    "INSERT INTO `stock` VALUES ('TST3', NULL, 'Energy', 'TESTX')");

-- -----------------------------------------------------
-- stock_price_history
-- -----------------------------------------------------
-- C.5.1: a second record for the same stock and day
CALL expect_rejected('C.5.1 price: duplicate (ticker, price_date)', 1062,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-30', 100, 100, 100, 100, 0)");
-- C.5.2: stock doesn't exist
CALL expect_rejected('C.5.2 price: unknown ticker', 1452,
    "INSERT INTO `stock_price_history` VALUES ('NOPE', '2026-09-29', 100, 100, 100, 100, 0)");
-- C.5.3: zero low price (the open/close are still inside low-high, so only C.5.3 fails)
CALL expect_rejected('C.5.3 price: low_price = 0', 3819,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 100, 100, 100, 0, 0)");
-- C.5.4: high below low
CALL expect_rejected('C.5.4 price: high_price < low_price', 3819,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 100, 100, 99, 101, 0)");
-- C.5.5: open above the high
CALL expect_rejected('C.5.5 price: opening_price > high_price', 3819,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 103, 100, 102, 99, 0)");
-- C.5.5: close below the low
CALL expect_rejected('C.5.5 price: closing_price < low_price', 3819,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 100, 98, 102, 99, 0)");
-- C.5.6: negative volume
CALL expect_rejected('C.5.6 price: volume = -1', 3819,
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 100, 100, 102, 99, -1)");
-- C.5.5 / C.5.6 boundary: open = high, close = low and zero volume are all allowed
CALL expect_accepted('C.5.5 price: open = high, close = low, volume = 0 allowed',
    "INSERT INTO `stock_price_history` VALUES ('TST', '2026-09-29', 110, 90, 110, 90, 0)");
-- C.5.7: tomorrow (trigger, since CHECKs can't call CURDATE())
CALL expect_rejected('C.5.7 price: price_date tomorrow', 1644,
    "INSERT INTO `stock_price_history` VALUES ('TST', CURDATE() + INTERVAL 1 DAY, 100, 100, 100, 100, 0)");
-- C.5.7: moving an existing record into the future (BEFORE UPDATE trigger)
CALL expect_rejected('C.5.7 price: update price_date to tomorrow', 1644,
    "UPDATE `stock_price_history` SET `price_date` = CURDATE() + INTERVAL 1 DAY WHERE `ticker` = 'TST' AND `price_date` = '2026-09-30'");
-- C.5.7 boundary: today is allowed
CALL expect_accepted('C.5.7 price: price_date today allowed',
    "INSERT INTO `stock_price_history` VALUES ('TST', CURDATE(), 100, 100, 100, 100, 0)");

-- -----------------------------------------------------
-- watchlist
-- -----------------------------------------------------
-- C.6.1: watching the same stock twice
CALL expect_rejected('C.6.1 watchlist: duplicate (user_id, ticker)', 1062,
    "INSERT INTO `watchlist` (`user_id`, `ticker`) VALUES (9001, 'TST2')");
-- C.6.2: user doesn't exist
CALL expect_rejected('C.6.2 watchlist: unknown user_id', 1452,
    "INSERT INTO `watchlist` (`user_id`, `ticker`) VALUES (999999, 'TST')");
-- C.6.3: stock doesn't exist
CALL expect_rejected('C.6.3 watchlist: unknown ticker', 1452,
    "INSERT INTO `watchlist` (`user_id`, `ticker`) VALUES (9001, 'NOPE')");
-- C.6.4: zero target price
CALL expect_rejected('C.6.4 watchlist: target_price = 0', 3819,
    "INSERT INTO `watchlist` (`user_id`, `ticker`, `target_price`) VALUES (9001, 'TST', 0)");
-- C.6.4 boundary: NULL means no alert and is allowed
CALL expect_accepted('C.6.4 watchlist: NULL target_price allowed',
    "INSERT INTO `watchlist` (`user_id`, `ticker`, `target_price`) VALUES (9001, 'TST', NULL)");
-- C.6.5: fixture rows were inserted without added_at
CALL expect_true('C.6.5 watchlist: added_at defaults to now',
    "SELECT `added_at` IS NOT NULL FROM `watchlist` WHERE `user_id` = 9001 AND `ticker` = 'TST2'");

-- -----------------------------------------------------
-- transaction
--   user 9001 starts this section with 500.00 cash and 5 TST in portfolio 9001.
--   Rejected inserts use buys of small cost, so the trigger lets them through to
--   the constraint under test.
-- -----------------------------------------------------
-- C.7.1: reusing a transaction_id
CALL expect_rejected('C.7.1 transaction: duplicate transaction_id', 1062,
    "INSERT INTO `transaction` VALUES (90001, 9001, 'TST', 'buy', 1, 1.00, '2026-09-30 11:00:00')");
-- C.7.2: portfolio doesn't exist
CALL expect_rejected('C.7.2 transaction: unknown portfolio_id', 1452,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (999999, 'TST', 'buy', 1, 1.00)");
-- C.7.2: stock doesn't exist
CALL expect_rejected('C.7.2 transaction: unknown ticker', 1452,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'NOPE', 'buy', 1, 1.00)");
-- C.7.2: no stock
CALL expect_rejected('C.7.2 transaction: NULL ticker', 1048,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, NULL, 'buy', 1, 1.00)");
-- C.7.3: zero shares
CALL expect_rejected('C.7.3 transaction: quantity = 0', 3819,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 0, 1.00)");
-- C.7.3: a negative sell would pass the holdings check and add shares
CALL expect_rejected('C.7.3 transaction: sell quantity = -1', 3819,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'sell', -1, 1.00)");
-- C.7.4: zero price
CALL expect_rejected('C.7.4 transaction: price = 0', 3819,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 1, 0)");
-- C.7.4: a negative-price buy would pass the cash check and credit cash
CALL expect_rejected('C.7.4 transaction: buy price < 0', 3819,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 1, -1.00)");
-- C.7.5: not buy or sell (the ENUM rejects it)
CALL expect_rejected('C.7.5 transaction: transaction_type short', 1265,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'short', 1, 1.00)");
-- C.7.5: no type
CALL expect_rejected('C.7.5 transaction: NULL transaction_type', 1048,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', NULL, 1, 1.00)");
-- C.7.6: editing a trade
CALL expect_rejected('C.7.6 transaction: UPDATE rejected', 1644,
    "UPDATE `transaction` SET `quantity` = 6 WHERE `transaction_id` = 90001");
-- C.7.6: deleting a trade
CALL expect_rejected('C.7.6 transaction: DELETE rejected', 1644,
    "DELETE FROM `transaction` WHERE `transaction_id` = 90001");
-- C.7.7: one cent more than the 500.00 available
CALL expect_rejected('C.7.7 transaction: buy costs cash + 0.01', 1644,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 1, 500.01)");
-- C.7.7: cash is per user, so another portfolio of the same user has no extra
CALL expect_rejected('C.7.7 transaction: other portfolio shares the same cash', 1644,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9002, 'TST', 'buy', 1, 500.01)");
-- C.7.8: one share more than the 5 held
CALL expect_rejected('C.7.8 transaction: sell holdings + 1', 1644,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'sell', 6, 100.00)");
-- C.7.8: holdings are per portfolio, so 9002 holds no TST
CALL expect_rejected('C.7.8 transaction: sell from a portfolio that holds none', 1644,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9002, 'TST', 'sell', 1, 100.00)");
-- C.7.10: tomorrow
CALL expect_rejected('C.7.10 transaction: executed_at tomorrow', 1644,
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`, `executed_at`) VALUES (9001, 'TST', 'buy', 1, 1.00, NOW() + INTERVAL 1 DAY)");
-- C.7.9: a sell credits cash: 500.00 + 2 x 150.00 = 800.00, leaving 3 TST
CALL expect_accepted('C.7.9 transaction: sell 2 @ 150.00',
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'sell', 2, 150.00)");
CALL expect_true('C.7.9 transaction: sell credited cash to 800.00',
    "SELECT `cash_balance` = 800.00 FROM `user` WHERE `user_id` = 9001");
-- C.7.9: a buy debits the cost rounded to cents: 3 x 33.3333 = 99.9999 -> 100.00
CALL expect_accepted('C.7.9 transaction: buy 3 @ 33.3333',
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 3, 33.3333)");
CALL expect_true('C.7.9 transaction: buy debited the rounded cost, cash 700.00',
    "SELECT `cash_balance` = 700.00 FROM `user` WHERE `user_id` = 9001");
-- C.7.8 boundary: selling every share held (3 + 3 = 6) is allowed; cash 700.00 + 600.00
CALL expect_accepted('C.7.8 transaction: sell exactly all 6 shares allowed',
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'sell', 6, 100.00)");
-- C.7.7 boundary: spending exactly all 1300.00 is allowed and leaves 0.00 (C.1.5)
CALL expect_accepted('C.7.7 transaction: buy costing exactly all cash allowed',
    "INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`) VALUES (9001, 'TST', 'buy', 13, 100.00)");
CALL expect_true('C.7.7 transaction: cash is now exactly 0.00',
    "SELECT `cash_balance` = 0.00 FROM `user` WHERE `user_id` = 9001");
-- C.7.10: executed_at defaults to now
CALL expect_true('C.7.10 transaction: executed_at defaults to now',
    "SELECT `executed_at` >= NOW() - INTERVAL 1 MINUTE FROM `transaction` WHERE `portfolio_id` = 9001 ORDER BY `transaction_id` DESC LIMIT 1");

-- -----------------------------------------------------
-- limit_order
--   user 9001 now has 0.00 cash and 13 TST in portfolio 9001.
-- -----------------------------------------------------
-- C.8.2: portfolio doesn't exist
CALL expect_rejected('C.8.2 limit_order: unknown portfolio_id', 1452,
    "INSERT INTO `limit_order` (`portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES (999999, 'TST', 'buy', 1.00, 1)");
-- C.8.2: stock doesn't exist
CALL expect_rejected('C.8.2 limit_order: unknown ticker', 1452,
    "INSERT INTO `limit_order` (`portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES (9001, 'NOPE', 'buy', 1.00, 1)");
-- C.8.3: zero target price
CALL expect_rejected('C.8.3 limit_order: target_price = 0', 3819,
    "INSERT INTO `limit_order` (`portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES (9001, 'TST', 'buy', 0, 1)");
-- C.8.3: zero quantity
CALL expect_rejected('C.8.3 limit_order: quantity = 0', 3819,
    "INSERT INTO `limit_order` (`portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES (9001, 'TST', 'buy', 1.00, 0)");
-- C.8.4: not buy or sell (the ENUM rejects it)
CALL expect_rejected('C.8.4 limit_order: order_type short', 1265,
    "INSERT INTO `limit_order` (`portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES (9001, 'TST', 'short', 1.00, 1)");
-- C.8.5, C.8.9: fixture orders were inserted without status or created_at
CALL expect_true('C.8.5 limit_order: status defaults to pending',
    "SELECT `status` = 'pending' FROM `limit_order` WHERE `order_id` = 9001");
CALL expect_true('C.8.9 limit_order: created_at defaults to now',
    "SELECT `created_at` IS NOT NULL FROM `limit_order` WHERE `order_id` = 9001");

-- Orders for the execution tests, placed directly (placement isn't checked against cash)
INSERT INTO `limit_order` (`order_id`, `portfolio_id`, `ticker`, `order_type`, `target_price`, `quantity`) VALUES
    (9010, 9001, 'TST', 'buy', 50.00, 1),     -- can't execute: no cash left
    (9011, 9001, 'TST', 'sell', 110.00, 3),   -- can execute: 13 held
    (9012, 9001, 'TST', 'sell', 110.00, 100), -- can't execute: only 13 held
    (9013, 9001, 'TST', 'buy', 1.00, 1);      -- cancelled below

-- C.8.8: executing a buy re-checks cash (0.00 < 50.00); the whole UPDATE rolls back
CALL expect_rejected('C.8.8 limit_order: execute buy without cash', 1644,
    "UPDATE `limit_order` SET `status` = 'executed' WHERE `order_id` = 9010");
CALL expect_true('C.8.8 limit_order: rejected order is still pending',
    "SELECT `status` = 'pending' FROM `limit_order` WHERE `order_id` = 9010");
-- C.8.8: executing a sell re-checks holdings (100 > 13), though placement wasn't checked
CALL expect_rejected('C.8.8 limit_order: execute sell beyond holdings', 1644,
    "UPDATE `limit_order` SET `status` = 'executed' WHERE `order_id` = 9012");
-- C.8.7: executing creates the matching trade at the target price; cash 3 x 110.00 = 330.00
CALL expect_accepted('C.8.7 limit_order: execute sell 3 @ 110.00',
    "UPDATE `limit_order` SET `status` = 'executed' WHERE `order_id` = 9011");
CALL expect_true('C.8.7 limit_order: matching transaction created',
    "SELECT COUNT(*) = 1 FROM `transaction` WHERE `portfolio_id` = 9001 AND `ticker` = 'TST' AND `transaction_type` = 'sell' AND `quantity` = 3 AND `price` = 110.00");
CALL expect_true('C.8.7 limit_order: trade credited cash to 330.00',
    "SELECT `cash_balance` = 330.00 FROM `user` WHERE `user_id` = 9001");
-- C.8.6: an executed order is final
CALL expect_rejected('C.8.6 limit_order: executed -> pending', 1644,
    "UPDATE `limit_order` SET `status` = 'pending' WHERE `order_id` = 9011");
-- C.8.6: final means no field can change, not only status
CALL expect_rejected('C.8.6 limit_order: change quantity of executed order', 1644,
    "UPDATE `limit_order` SET `quantity` = 1 WHERE `order_id` = 9011");
-- C.8.6 boundary: a pending order can be cancelled
CALL expect_accepted('C.8.6 limit_order: pending -> cancelled allowed',
    "UPDATE `limit_order` SET `status` = 'cancelled' WHERE `order_id` = 9013");
-- C.8.6: a cancelled order is final
CALL expect_rejected('C.8.6 limit_order: cancelled -> executed', 1644,
    "UPDATE `limit_order` SET `status` = 'executed' WHERE `order_id` = 9013");

-- -----------------------------------------------------
-- Deletes and cascades (last, since they remove fixtures)
-- -----------------------------------------------------
-- C.7.11: a portfolio with trades can't be deleted
CALL expect_rejected('C.7.11 delete portfolio that has trades', 1451,
    "DELETE FROM `portfolio` WHERE `portfolio_id` = 9001");
-- C.2.3 + C.7.11: the cascade to portfolios hits trades, so the user delete fails
CALL expect_rejected('C.2.3 delete user whose portfolio has trades', 1451,
    "DELETE FROM `user` WHERE `user_id` = 9001");
-- C.7.11: a stock with trades can't be deleted
CALL expect_rejected('C.7.11 delete stock that has trades', 1451,
    "DELETE FROM `stock` WHERE `ticker` = 'TST'");
-- C.4.3: an exchange with listed stocks can't be deleted
CALL expect_rejected('C.4.3 delete exchange with listed stocks', 1451,
    "DELETE FROM `exchange` WHERE `exchange_code` = 'TESTX'");
-- C.2.3, C.6.2, C.8.2: a user without trades is deleted with portfolios, watchlist and orders
CALL expect_accepted('C.2.3 delete user without trades',
    "DELETE FROM `user` WHERE `user_id` = 9002");
CALL expect_true('C.2.3 cascade removed portfolios, watchlist and orders',
    "(SELECT COUNT(*) FROM `portfolio` WHERE `user_id` = 9002) + (SELECT COUNT(*) FROM `watchlist` WHERE `user_id` = 9002) + (SELECT COUNT(*) FROM `limit_order` WHERE `order_id` = 9001) = 0");
-- C.5.2, C.6.3, C.8.2: a stock without trades is deleted with its prices, watchers and orders
CALL expect_accepted('C.5.2 delete stock without trades',
    "DELETE FROM `stock` WHERE `ticker` = 'TST2'");
CALL expect_true('C.5.2 cascade removed price history, watchlist and orders',
    "(SELECT COUNT(*) FROM `stock_price_history` WHERE `ticker` = 'TST2') + (SELECT COUNT(*) FROM `watchlist` WHERE `ticker` = 'TST2') + (SELECT COUNT(*) FROM `limit_order` WHERE `ticker` = 'TST2') = 0");

ROLLBACK;

-- -----------------------------------------------------
-- Report
-- -----------------------------------------------------
INSERT INTO `constraint_test_results`
SELECT 'rollback: row counts unchanged', NULL, NULL, @counts_before = CONCAT_WS('/',
    (SELECT COUNT(*) FROM `exchange`), (SELECT COUNT(*) FROM `stock`),
    (SELECT COUNT(*) FROM `stock_price_history`), (SELECT COUNT(*) FROM `user`),
    (SELECT COUNT(*) FROM `portfolio`), (SELECT COUNT(*) FROM `watchlist`),
    (SELECT COUNT(*) FROM `transaction`), (SELECT COUNT(*) FROM `limit_order`)),
    CONCAT('before ', @counts_before);

SELECT `test`, `expected_code`, `actual_code`, IF(`passed`, 'PASS', 'FAIL') AS `result`, `message`
FROM `constraint_test_results`;

SELECT SUM(`passed`) AS `passed`, COUNT(*) AS `total` FROM `constraint_test_results`;

DROP PROCEDURE `expect_rejected`;
DROP PROCEDURE `expect_accepted`;
DROP PROCEDURE `expect_true`;
CALL assert_all_passed();
DROP PROCEDURE `assert_all_passed`;
