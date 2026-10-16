-- Initialize Database and potentially remove outdated db
DROP DATABASE IF EXISTS stock_trading;
CREATE DATABASE stock_trading;
USE stock_trading;

-- Constraints follow docs/Relational Algebra Constraints/ra-constraints.tex

-- -----------------------------------------------------
-- Entity User
-- -----------------------------------------------------
CREATE TABLE `user`
(
    `user_id` INT          NOT NULL,
    `name`    VARCHAR(100) NOT NULL,
    `email`   VARCHAR(255) NOT NULL,
    -- Key: no two distinct users share a user_id
    CONSTRAINT `pk_user` PRIMARY KEY (`user_id`),
    -- Candidate key: an email address registers at most one account (email -> user_id)
    CONSTRAINT `uq_user_email` UNIQUE (`email`)
);

-- -----------------------------------------------------
-- Entity Stock
-- -----------------------------------------------------
CREATE TABLE `stock` (
    `ticker` VARCHAR(10) NOT NULL,
    `company_name` VARCHAR(100) NOT NULL,
    `opening_price` DECIMAL(12, 4) NOT NULL,
    `closing_price` DECIMAL(12, 4) NOT NULL,
    `exchange` VARCHAR(20) NOT NULL,
    -- Key: no two distinct stocks share a ticker
    CONSTRAINT `pk_stock` PRIMARY KEY (`ticker`),
    -- Domain: sigma_{opening_price <= 0}(Stock) = empty
    CONSTRAINT `chk_stock_opening_price` CHECK (`opening_price` > 0),
    -- Domain: sigma_{closing_price <= 0}(Stock) = empty
    CONSTRAINT `chk_stock_closing_price` CHECK (`closing_price` > 0)
);

-- ----------------------------------------------------
-- Entity Transaction
--  Places (User 1 : N Transaction)
--  Involves (Stock 1 : N Transaction)
-- -----------------------------------------------------
CREATE TABLE `transaction` (
    `transaction_id` INT NOT NULL,
    `user_id` INT NOT NULL,
    `ticker` VARCHAR(10) NOT NULL,
    `transaction_type` ENUM('buy', 'sell') NOT NULL,
    `quantity` INT NOT NULL,
    `price` DECIMAL(12, 4) NOT NULL,
    `time` DATETIME NOT NULL,
    -- Key: no two distinct transactions share a transaction_id
    CONSTRAINT `pk_transaction` PRIMARY KEY (`transaction_id`),
    -- Referential integrity: pi_user_id(Transaction) subset of pi_user_id(User)
    CONSTRAINT `fk_transaction_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`),
    -- Referential integrity: pi_ticker(Transaction) subset of pi_ticker(Stock)
    CONSTRAINT `fk_transaction_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`),
    -- Domain: sigma_{quantity <= 0}(Transaction) = empty
    CONSTRAINT `chk_transaction_quantity` CHECK (`quantity` > 0),
    -- Domain: sigma_{price <= 0}(Transaction) = empty
    CONSTRAINT `chk_transaction_price` CHECK (`price` > 0),
    -- Domain: sigma_{transaction_type not in {'buy', 'sell'}}(Transaction) = empty
    CONSTRAINT `chk_transaction_type` CHECK (`transaction_type` IN ('buy', 'sell'))
);

-- -----------------------------------------------------
-- Relationship: Holds (User M : N Stock)
--   Relationship attributes: quantity, average_price
-- -----------------------------------------------------
CREATE TABLE `holds` (
    `user_id` INT NOT NULL,
    `ticker` VARCHAR(10) NOT NULL,
    `quantity` INT NOT NULL,
    `average_price` DECIMAL(12, 4) NOT NULL,
    -- Composite key: a user has at most one holding per ticker
    CONSTRAINT `pk_holds` PRIMARY KEY (`user_id`, `ticker`),
    -- Referential integrity: pi_user_id(Holds) subset of pi_user_id(User)
    CONSTRAINT `fk_holds_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`),
    -- Referential integrity: pi_ticker(Holds) subset of pi_ticker(Stock)
    CONSTRAINT `fk_holds_stock` FOREIGN KEY (`ticker`) REFERENCES `stock` (`ticker`),
    -- Domain: sigma_{quantity < 0}(Holds) = empty
    CONSTRAINT `chk_holds_quantity` CHECK (`quantity` >= 0),
    -- Domain: sigma_{average_price <= 0}(Holds) = empty
    CONSTRAINT `chk_holds_average_price` CHECK (`average_price` > 0)
);
