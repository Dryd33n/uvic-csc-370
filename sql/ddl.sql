-- Initialize Database and potentially remove outdated db
DROP DATABASE IF EXISTS stock_trading;
CREATE DATABASE stock_trading;
USE stock_trading;

-- -----------------------------------------------------
-- Entity User
-- -----------------------------------------------------
CREATE TABLE `user`
(
    `user_id` INT          NOT NULL,
    `name`    VARCHAR(100) NOT NULL,
    `email`   VARCHAR(255) NOT NULL
);

-- -----------------------------------------------------
-- Entity Stock
-- -----------------------------------------------------
CREATE TABLE `stock` (
    `ticker` VARCHAR(10) NOT NULL,
    `company_name` VARCHAR(100) NOT NULL,
    `opening_price` DECIMAL(12, 4) NOT NULL,
    `closing_price` DECIMAL(12, 4) NOT NULL,
    `exchange` VARCHAR(20) NOT NULL
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
    `time` DATETIME NOT NULL
);

-- -----------------------------------------------------
-- Relationship: Holds (User M : N Stock)
--   Relationship attributes: quantity, average_price
-- -----------------------------------------------------
CREATE TABLE `holds` (
    `user_id` INT NOT NULL,
    `ticker` VARCHAR(10) NOT NULL,
    `quantity` INT NOT NULL,
    `average_price` DECIMAL(12, 4) NOT NULL
);
