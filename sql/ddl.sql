-- Initialize Database and potentially remove outdated db
DROP DATABASE IF EXISTS stock_trading;
CREATE DATABASE stock_trading;
USE stock_trading;

-- -----------------------------------------------------
-- Entity User
-- -----------------------------------------------------
CREATE TABLE `user`
(
    `user_id` INT,
    `name`    VARCHAR(100),
    `email`   VARCHAR(255)
);

-- -----------------------------------------------------
-- Entity Stock
-- -----------------------------------------------------
CREATE TABLE `stock` (
    `ticker` VARCHAR(10),
    `company_name` VARCHAR(100),
    `opening_price` DECIMAL(12, 4),
    `closing_price` DECIMAL(12, 4),
    `exchange` VARCHAR(20)
);

-- ----------------------------------------------------
-- Entity Transaction
--  Places (User 1 : N Transaction)
--  Involves (Stock 1 : N Transaction)
-- -----------------------------------------------------
CREATE TABLE `transaction` (
    `transaction_id` INT,
    `user_id` INT,
    `ticker` VARCHAR(10),
    `transaction_type` ENUM('buy', 'sell'),
    `quantity` INT,
    `price` DECIMAL(12, 4),
    `time` DATETIME
);

-- -----------------------------------------------------
-- Relationship: Holds (User M : N Stock)
--   Relationship attributes: quantity, average_price
-- -----------------------------------------------------
CREATE TABLE `holds` (
    `user_id` INT,
    `ticker` VARCHAR(10),
    `quantity` INT,
    `average_price` DECIMAL(12, 4)
);
