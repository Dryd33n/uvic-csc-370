-- Constraint tests for sql/ddl.sql
--   Each test runs one statement that breaks exactly one constraint, and passes
--   only if MySQL rejects it with the expected error code. Checking the code
--   (not just "some error") means a typo or syntax error cannot count as a pass.
--   Run after ddl.sql and seed.sql. All changes are rolled back, so the seed
--   data is unchanged. Exits with an error if any test fails, so CI fails too.

USE stock_trading;

-- Expected MySQL error codes
--   1062  ER_DUP_ENTRY                   duplicate primary key or UNIQUE value
--   1452  ER_NO_REFERENCED_ROW_2         foreign key points to a missing parent row
--   1451  ER_ROW_IS_REFERENCED_2         parent row is still referenced by a child row
--   3819  ER_CHECK_CONSTRAINT_VIOLATED   CHECK constraint is false
--   1265  WARN_DATA_TRUNCATED            value not in the ENUM (an error in strict mode)

-- -----------------------------------------------------
-- Test harness
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS `expect_rejected`;
DROP PROCEDURE IF EXISTS `assert_all_rejected`;

-- MEMORY tables are not transactional, so results survive the final ROLLBACK
DROP TEMPORARY TABLE IF EXISTS `constraint_test_results`;
CREATE TEMPORARY TABLE `constraint_test_results` (
    `test`          VARCHAR(100) NOT NULL,
    `expected_code` INT          NULL,
    `actual_code`   INT          NULL,      -- NULL means the statement was accepted
    `passed`        BOOLEAN      NOT NULL,
    `message`       VARCHAR(512) NULL
) ENGINE = MEMORY;

DELIMITER //

-- Runs `stmt` and records whether it failed with `expected_code`
CREATE PROCEDURE `expect_rejected`(IN test_name VARCHAR(100), IN expected_code INT, IN stmt TEXT)
BEGIN
    DECLARE actual_code INT DEFAULT NULL;
    DECLARE message VARCHAR(512) DEFAULT 'accepted: constraint did not reject the statement';

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

-- Raises an error if any test failed, so the mysql client exits non-zero
CREATE PROCEDURE `assert_all_rejected`()
BEGIN
    DECLARE failures INT;
    SELECT COUNT(*) INTO failures FROM `constraint_test_results` WHERE NOT `passed`;
    IF failures > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Constraint tests failed: see the results table above';
    END IF;
END //

DELIMITER ;

-- Outside strict mode, MySQL stores a bad ENUM value as '' with only a warning,
-- so the ENUM test below would pass without rejecting anything
INSERT INTO `constraint_test_results`
VALUES ('server: sql_mode is strict', NULL, NULL,
        @@SESSION.sql_mode LIKE '%STRICT_TRANS_TABLES%' OR @@SESSION.sql_mode LIKE '%STRICT_ALL_TABLES%',
        @@SESSION.sql_mode);

START TRANSACTION;

-- -----------------------------------------------------
-- Key and uniqueness constraints
-- -----------------------------------------------------
CALL expect_rejected('pk_user: duplicate user_id', 1062,
    "INSERT INTO `user` VALUES (1, 'Duplicate Id', 'duplicate.id@example.com')");
CALL expect_rejected('uq_user_email: duplicate email', 1062,
    "INSERT INTO `user` VALUES (100, 'Duplicate Email', 'alice@example.com')");
CALL expect_rejected('pk_stock: duplicate ticker', 1062,
    "INSERT INTO `stock` VALUES ('AAPL', 'Duplicate Apple', 100.00, 100.00, 'NASDAQ')");
CALL expect_rejected('pk_transaction: duplicate transaction_id', 1062,
    "INSERT INTO `transaction` VALUES (1, 1, 'AAPL', 'buy', 1, 100.00, '2026-09-30 10:00:00')");
CALL expect_rejected('pk_holds: duplicate (user_id, ticker)', 1062,
    "INSERT INTO `holds` VALUES (1, 'AAPL', 5, 100.00)");

-- -----------------------------------------------------
-- Referential integrity: child rows need a parent
-- -----------------------------------------------------
CALL expect_rejected('fk_transaction_user: unknown user_id', 1452,
    "INSERT INTO `transaction` VALUES (1000, 999, 'AAPL', 'buy', 1, 100.00, '2026-09-30 10:00:00')");
CALL expect_rejected('fk_transaction_stock: unknown ticker', 1452,
    "INSERT INTO `transaction` VALUES (1000, 1, 'ZZZZ', 'buy', 1, 100.00, '2026-09-30 10:00:00')");
CALL expect_rejected('fk_holds_user: unknown user_id', 1452,
    "INSERT INTO `holds` VALUES (999, 'AAPL', 5, 100.00)");
CALL expect_rejected('fk_holds_stock: unknown ticker', 1452,
    "INSERT INTO `holds` VALUES (1, 'ZZZZ', 5, 100.00)");

-- -----------------------------------------------------
-- Referential integrity: parent rows still in use cannot be removed
-- -----------------------------------------------------
CALL expect_rejected('fk to user: delete a user who has trades', 1451,
    "DELETE FROM `user` WHERE `user_id` = 1");
CALL expect_rejected('fk to stock: delete a stock that has trades', 1451,
    "DELETE FROM `stock` WHERE `ticker` = 'AAPL'");
CALL expect_rejected('fk to user: change a referenced user_id', 1451,
    "UPDATE `user` SET `user_id` = 500 WHERE `user_id` = 1");

-- -----------------------------------------------------
-- Domain constraints
-- -----------------------------------------------------
CALL expect_rejected('chk_transaction_quantity: quantity = 0', 3819,
    "INSERT INTO `transaction` VALUES (1000, 1, 'AAPL', 'buy', 0, 100.00, '2026-09-30 10:00:00')");
CALL expect_rejected('chk_transaction_quantity: quantity < 0 (update)', 3819,
    "UPDATE `transaction` SET `quantity` = -5 WHERE `transaction_id` = 1");
CALL expect_rejected('chk_transaction_price: price = 0', 3819,
    "INSERT INTO `transaction` VALUES (1000, 1, 'AAPL', 'buy', 1, 0.00, '2026-09-30 10:00:00')");
CALL expect_rejected('chk_transaction_price: price < 0 (update)', 3819,
    "UPDATE `transaction` SET `price` = -1.00 WHERE `transaction_id` = 1");
-- The ENUM rejects the value before chk_transaction_type is evaluated
CALL expect_rejected('transaction_type: not buy or sell', 1265,
    "INSERT INTO `transaction` VALUES (1000, 1, 'AAPL', 'short', 1, 100.00, '2026-09-30 10:00:00')");
CALL expect_rejected('chk_holds_quantity: quantity < 0', 3819,
    "INSERT INTO `holds` VALUES (9, 'AAPL', -1, 100.00)");
CALL expect_rejected('chk_holds_average_price: average_price = 0', 3819,
    "INSERT INTO `holds` VALUES (9, 'AAPL', 5, 0.00)");
CALL expect_rejected('chk_stock_opening_price: opening_price = 0', 3819,
    "INSERT INTO `stock` VALUES ('TEST', 'Test Corp', 0.00, 10.00, 'NYSE')");
CALL expect_rejected('chk_stock_closing_price: closing_price < 0', 3819,
    "INSERT INTO `stock` VALUES ('TEST', 'Test Corp', 10.00, -10.00, 'NYSE')");

ROLLBACK;

-- -----------------------------------------------------
-- Report
-- -----------------------------------------------------
SELECT `test`, `expected_code`, `actual_code`, IF(`passed`, 'PASS', 'FAIL') AS `result`, `message`
FROM `constraint_test_results`;

SELECT SUM(`passed`) AS `passed`, COUNT(*) AS `total` FROM `constraint_test_results`;

-- Row counts must match the seed data (9 / 14 / 82 / 22) after the rollback
SELECT (SELECT COUNT(*) FROM `user`)        AS `users`,
       (SELECT COUNT(*) FROM `stock`)       AS `stocks`,
       (SELECT COUNT(*) FROM `transaction`) AS `transactions`,
       (SELECT COUNT(*) FROM `holds`)       AS `holds`;

DROP PROCEDURE `expect_rejected`;
CALL assert_all_rejected();
DROP PROCEDURE `assert_all_rejected`;
