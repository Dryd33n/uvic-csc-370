-- Initialize Database and potentially remove outdated db
DROP DATABASE IF EXISTS stock_trading;
CREATE DATABASE stock_trading;
USE stock_trading;

-- Constraint IDs (C.x.y) follow docs/Schemata Overview/schemata.md

-- -----------------------------------------------------
-- Entity User
-- -----------------------------------------------------
CREATE TABLE `user` (
    `user_id`      INT            NOT NULL AUTO_INCREMENT,
    `name`         VARCHAR(100)   NOT NULL,
    `email`        VARCHAR(255)   NOT NULL,
    -- C.1.6: new accounts start with a fixed amount of paper money
    `cash_balance` DECIMAL(12, 2) NOT NULL DEFAULT 100000.00,
    -- C.1.1
    CONSTRAINT `pk_user` PRIMARY KEY (`user_id`),
    -- C.1.2: an email address registers at most one account
    CONSTRAINT `uq_user_email` UNIQUE (`email`),
    -- C.1.4
    CONSTRAINT `chk_user_email` CHECK (`email` LIKE '%_@_%._%'),
    -- C.1.5
    CONSTRAINT `chk_user_cash_balance` CHECK (`cash_balance` >= 0)
);

-- -----------------------------------------------------
-- Entity Portfolio
--   Owns (User 1 : N Portfolio)
-- -----------------------------------------------------
CREATE TABLE `portfolio` (
    `portfolio_id`   INT          NOT NULL AUTO_INCREMENT,
    `user_id`        INT          NOT NULL,
    `portfolio_name` VARCHAR(100) NOT NULL,
    -- C.2.6
    `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- C.2.1
    CONSTRAINT `pk_portfolio` PRIMARY KEY (`portfolio_id`),
    -- C.2.2, C.2.3: blocked by C.7.11 if any portfolio has transactions
    CONSTRAINT `fk_portfolio_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`)
        ON DELETE CASCADE,
    -- C.2.4: names are unique per user, not globally
    CONSTRAINT `uq_portfolio_user_name` UNIQUE (`user_id`, `portfolio_name`),
    -- C.2.5
    CONSTRAINT `chk_portfolio_name` CHECK (`portfolio_name` <> '')
);

-- -----------------------------------------------------
-- Entity Exchange
-- -----------------------------------------------------
CREATE TABLE `exchange` (
    `exchange_code` VARCHAR(10)  NOT NULL,
    `exchange_name` VARCHAR(100) NOT NULL,
    `country`       VARCHAR(50)  NOT NULL,
    `currency`      VARCHAR(10)  NOT NULL,
    -- C.3.1
    CONSTRAINT `pk_exchange` PRIMARY KEY (`exchange_code`),
    -- C.3.3: ISO 4217 code, e.g. USD, CAD
    CONSTRAINT `chk_exchange_currency` CHECK (CHAR_LENGTH(`currency`) = 3),
    -- C.3.4: compared as binary, since the default collation ignores case
    CONSTRAINT `chk_exchange_code_upper`
        CHECK (CAST(`exchange_code` AS BINARY) = CAST(UPPER(`exchange_code`) AS BINARY))
);

-- -----------------------------------------------------
-- Entity Stock
--   Lists (Exchange 1 : N Stock)
-- -----------------------------------------------------
CREATE TABLE `stock` (
    `ticker`        VARCHAR(10)  NOT NULL,
    `company_name`  VARCHAR(100) NOT NULL,
    `sector`        VARCHAR(50)  NULL,
    `exchange_code` VARCHAR(10)  NOT NULL,
    -- C.4.1
    CONSTRAINT `pk_stock` PRIMARY KEY (`ticker`),
    -- C.4.2, C.4.3: an exchange can't be deleted while stocks are listed on it
    CONSTRAINT `fk_stock_exchange` FOREIGN KEY (`exchange_code`) REFERENCES `exchange` (`exchange_code`)
        ON DELETE RESTRICT,
    -- C.4.4: compared as binary, since the default collation ignores case
    CONSTRAINT `chk_stock_ticker_upper`
        CHECK (CAST(`ticker` AS BINARY) = CAST(UPPER(`ticker`) AS BINARY))
);

-- -----------------------------------------------------
-- Weak Entity Stock Price History
--   Has (Stock 1 : N Stock Price History), identifying
-- -----------------------------------------------------
CREATE TABLE `stock_price_history` (
    `ticker`        VARCHAR(10)    NOT NULL,
    `price_date`    DATE           NOT NULL,
    `opening_price` DECIMAL(12, 4) NOT NULL,
    `closing_price` DECIMAL(12, 4) NOT NULL,
    `high_price`    DECIMAL(12, 4) NOT NULL,
    `low_price`     DECIMAL(12, 4) NOT NULL,
    `volume`        BIGINT         NOT NULL,
    -- C.5.1: one price record per stock per day
    CONSTRAINT `pk_stock_price_history` PRIMARY KEY (`ticker`, `price_date`),
    -- C.5.2
    CONSTRAINT `fk_stock_price_history_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`)
        ON DELETE CASCADE,
    -- C.5.3
    CONSTRAINT `chk_stock_price_history_opening` CHECK (`opening_price` > 0),
    CONSTRAINT `chk_stock_price_history_closing` CHECK (`closing_price` > 0),
    CONSTRAINT `chk_stock_price_history_high` CHECK (`high_price` > 0),
    CONSTRAINT `chk_stock_price_history_low` CHECK (`low_price` > 0),
    -- C.5.4
    CONSTRAINT `chk_stock_price_history_range` CHECK (`high_price` >= `low_price`),
    -- C.5.5
    CONSTRAINT `chk_stock_price_history_open_close`
        CHECK (`opening_price` BETWEEN `low_price` AND `high_price`
           AND `closing_price` BETWEEN `low_price` AND `high_price`),
    -- C.5.6
    CONSTRAINT `chk_stock_price_history_volume` CHECK (`volume` >= 0)
);

-- -----------------------------------------------------
-- Relationship: Watchlist (User M : N Stock)
--   Relationship attributes: target_price, added_at
-- -----------------------------------------------------
CREATE TABLE `watchlist` (
    `user_id`      INT            NOT NULL,
    `ticker`       VARCHAR(10)    NOT NULL,
    `target_price` DECIMAL(12, 4) NULL,
    -- C.6.5
    `added_at`     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- C.6.1: a user watches a given stock at most once
    CONSTRAINT `pk_watchlist` PRIMARY KEY (`user_id`, `ticker`),
    -- C.6.2
    CONSTRAINT `fk_watchlist_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`)
        ON DELETE CASCADE,
    -- C.6.3
    CONSTRAINT `fk_watchlist_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`)
        ON DELETE CASCADE,
    -- C.6.4: NULL means no price alert
    CONSTRAINT `chk_watchlist_target_price` CHECK (`target_price` > 0)
);

-- -----------------------------------------------------
-- Entity Transaction (immutable ledger)
--   Records (Portfolio 1 : N Transaction)
--   Involves (Stock 1 : N Transaction)
-- -----------------------------------------------------
CREATE TABLE `transaction` (
    `transaction_id`   INT                  NOT NULL AUTO_INCREMENT,
    `portfolio_id`     INT                  NOT NULL,
    `ticker`           VARCHAR(10)          NOT NULL,
    -- C.7.5
    `transaction_type` ENUM ('buy', 'sell') NOT NULL,
    `quantity`         INT                  NOT NULL,
    `price`            DECIMAL(12, 4)       NOT NULL,
    -- C.7.10 (default; the future check is a trigger)
    `executed_at`      DATETIME             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- C.7.1
    CONSTRAINT `pk_transaction` PRIMARY KEY (`transaction_id`),
    -- C.7.2, C.7.11: a portfolio with trades can't be deleted, so the ledger is never lost
    CONSTRAINT `fk_transaction_portfolio` FOREIGN KEY (`portfolio_id`) REFERENCES `portfolio` (`portfolio_id`)
        ON DELETE RESTRICT,
    -- C.7.2, C.7.11: a stock with trades can't be deleted
    CONSTRAINT `fk_transaction_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`)
        ON DELETE RESTRICT,
    -- C.7.3
    CONSTRAINT `chk_transaction_quantity` CHECK (`quantity` > 0),
    -- C.7.4
    CONSTRAINT `chk_transaction_price` CHECK (`price` > 0)
);

-- -----------------------------------------------------
-- Entity Limit Order
--   Places (Portfolio 1 : N Limit Order)
--   Targets (Stock 1 : N Limit Order)
-- -----------------------------------------------------
CREATE TABLE `limit_order` (
    `order_id`     INT                                        NOT NULL AUTO_INCREMENT,
    `portfolio_id` INT                                        NOT NULL,
    `ticker`       VARCHAR(10)                                NOT NULL,
    -- C.8.4
    `order_type`   ENUM ('buy', 'sell')                       NOT NULL,
    `target_price` DECIMAL(12, 4)                             NOT NULL,
    `quantity`     INT                                        NOT NULL,
    -- C.8.5
    `status`       ENUM ('pending', 'executed', 'cancelled')  NOT NULL DEFAULT 'pending',
    -- C.8.9
    `created_at`   DATETIME                                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- C.8.1
    CONSTRAINT `pk_limit_order` PRIMARY KEY (`order_id`),
    -- C.8.2
    CONSTRAINT `fk_limit_order_portfolio` FOREIGN KEY (`portfolio_id`) REFERENCES `portfolio` (`portfolio_id`)
        ON DELETE CASCADE,
    CONSTRAINT `fk_limit_order_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`)
        ON DELETE CASCADE,
    -- C.8.3
    CONSTRAINT `chk_limit_order_target_price` CHECK (`target_price` > 0),
    CONSTRAINT `chk_limit_order_quantity` CHECK (`quantity` > 0)
);

-- -----------------------------------------------------
-- Triggers
--   Rules a CHECK can't express: they read other rows or tables, or the clock.
--   Each rejects with SQLSTATE 45000 (MySQL error 1644).
-- -----------------------------------------------------
DELIMITER //

-- C.5.7: price_date can't be in the future (CHECKs can't call CURDATE())
CREATE TRIGGER `trg_stock_price_history_before_insert`
    BEFORE INSERT ON `stock_price_history`
    FOR EACH ROW
BEGIN
    IF NEW.price_date > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'price_date cannot be in the future';
    END IF;
END //

CREATE TRIGGER `trg_stock_price_history_before_update`
    BEFORE UPDATE ON `stock_price_history`
    FOR EACH ROW
BEGIN
    IF NEW.price_date > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'price_date cannot be in the future';
    END IF;
END //

-- C.7.7, C.7.8, C.7.10: validate a trade before it is recorded
CREATE TRIGGER `trg_transaction_before_insert`
    BEFORE INSERT ON `transaction`
    FOR EACH ROW
BEGIN
    DECLARE available_cash DECIMAL(12, 2);
    DECLARE shares_held INT;

    -- C.7.10
    IF NEW.executed_at > NOW() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'executed_at cannot be in the future';
    END IF;

    -- Locks the owner's row so two concurrent trades can't both pass the checks below.
    -- A missing portfolio leaves available_cash NULL; the FK then rejects the insert.
    SELECT u.cash_balance INTO available_cash
    FROM `user` u
             JOIN `portfolio` p ON p.user_id = u.user_id
    WHERE p.portfolio_id = NEW.portfolio_id
    FOR UPDATE;

    IF NEW.transaction_type = 'buy' THEN
        -- C.7.7
        IF ROUND(NEW.quantity * NEW.price, 2) > available_cash THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'insufficient cash_balance for this buy';
        END IF;
    ELSE
        -- C.7.8: holdings = bought - sold for this portfolio and ticker
        SELECT COALESCE(SUM(IF(t.transaction_type = 'buy', t.quantity, -t.quantity)), 0) INTO shares_held
        FROM `transaction` t
        WHERE t.portfolio_id = NEW.portfolio_id
          AND t.ticker = NEW.ticker;

        IF NEW.quantity > shares_held THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sell quantity exceeds shares held';
        END IF;
    END IF;
END //

-- C.7.9: a buy debits the owner's cash, a sell credits it
CREATE TRIGGER `trg_transaction_after_insert`
    AFTER INSERT ON `transaction`
    FOR EACH ROW
BEGIN
    UPDATE `user` u
        JOIN `portfolio` p ON p.user_id = u.user_id
    SET u.cash_balance = u.cash_balance
        + IF(NEW.transaction_type = 'buy', -1, 1) * ROUND(NEW.quantity * NEW.price, 2)
    WHERE p.portfolio_id = NEW.portfolio_id;
END //

-- C.7.6: transactions are immutable
CREATE TRIGGER `trg_transaction_before_update`
    BEFORE UPDATE ON `transaction`
    FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transactions are immutable and cannot be updated';
END //

CREATE TRIGGER `trg_transaction_before_delete`
    BEFORE DELETE ON `transaction`
    FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'transactions are immutable and cannot be deleted';
END //

-- C.8.6: once an order is executed or cancelled it is final
CREATE TRIGGER `trg_limit_order_before_update`
    BEFORE UPDATE ON `limit_order`
    FOR EACH ROW
BEGIN
    IF OLD.status <> 'pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'only pending orders can be changed';
    END IF;
END //

-- C.8.7, C.8.8: executing an order records the trade at the limit price. The insert
-- fires trg_transaction_before_insert, which re-checks cash and holdings; if that
-- rejects, the whole UPDATE is rolled back and the order stays pending.
CREATE TRIGGER `trg_limit_order_after_update`
    AFTER UPDATE ON `limit_order`
    FOR EACH ROW
BEGIN
    IF OLD.status = 'pending' AND NEW.status = 'executed' THEN
        INSERT INTO `transaction` (`portfolio_id`, `ticker`, `transaction_type`, `quantity`, `price`)
        VALUES (NEW.portfolio_id, NEW.ticker, NEW.order_type, NEW.quantity, NEW.target_price);
    END IF;
END //

DELIMITER ;
