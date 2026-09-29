USE stock_trading;

-- -----------------------------------------------------
-- user
-- -----------------------------------------------------
INSERT INTO `user` (`user_id`, `name`, `email`) VALUES
    (1, 'Alice Martin', 'alice@example.com'),
    (2, 'Ben Carter', 'ben@example.com'),
    (3, 'Chika Okafor', 'chika@example.com'),
    (4, 'Diego Ramirez', 'diego@example.com'),
    (5, 'Emma Tremblay', 'emma@example.com'),
    (6, 'Farhan Siddiqui', 'farhan@example.com'),
    (7, 'Grace Liu', 'grace@example.com'),
    (8, 'Hiroshi Tanaka', 'hiroshi@example.com'),
    (9, 'Isla MacDonald', 'isla@example.com');  -- no trades yet

-- -----------------------------------------------------
-- stock (prices are the 2026-09-28 session)
-- -----------------------------------------------------
INSERT INTO `stock` (`ticker`, `company_name`, `opening_price`, `closing_price`, `exchange`) VALUES
    ('AAPL', 'Apple Inc.', 217.85, 220.51, 'NASDAQ'),  -- Technology
    ('MSFT', 'Microsoft Corporation', 483.39, 483.82, 'NASDAQ'),  -- Technology
    ('NVDA', 'NVIDIA Corporation', 178.69, 173.06, 'NASDAQ'),  -- Semiconductors
    ('AMZN', 'Amazon.com, Inc.', 193.27, 195.00, 'NASDAQ'),  -- Consumer Discretionary
    ('GOOGL', 'Alphabet Inc. Class A', 176.16, 174.59, 'NASDAQ'),  -- Communication Services
    ('COST', 'Costco Wholesale Corporation', 928.28, 930.94, 'NASDAQ'),  -- Consumer Staples
    ('JPM', 'JPMorgan Chase & Co.', 268.04, 268.27, 'NYSE'),  -- Financials
    ('KO', 'The Coca-Cola Company', 66.05, 66.01, 'NYSE'),  -- Consumer Staples
    ('XOM', 'Exxon Mobil Corporation', 118.59, 118.15, 'NYSE'),  -- Energy
    ('JNJ', 'Johnson & Johnson', 162.19, 162.47, 'NYSE'),  -- Health Care
    ('DIS', 'The Walt Disney Company', 89.57, 89.65, 'NYSE'),  -- Communication Services
    ('CAT', 'Caterpillar Inc.', 386.83, 384.96, 'NYSE'),  -- Industrials
    ('CNR', 'Canadian National Railway Company', 154.13, 152.72, 'TSX'),  -- Industrials (CAD, watch only - never traded)
    ('ATD', 'Alimentation Couche-Tard Inc.', 74.32, 75.38, 'TSX');  -- Consumer Staples (CAD, watch only - never traded)

-- -----------------------------------------------------
-- transaction (ids in time order)
-- -----------------------------------------------------
INSERT INTO `transaction` (`transaction_id`, `user_id`, `ticker`, `transaction_type`, `quantity`, `price`, `time`) VALUES
    ( 1, 6, 'GOOGL', 'buy',   38,  181.53, '2026-09-01 11:06:18'),
    ( 2, 1, 'AAPL',  'buy',   13,  230.98, '2026-09-01 11:13:29'),
    ( 3, 1, 'MSFT',  'buy',    9,  442.30, '2026-09-01 11:45:10'),
    ( 4, 4, 'JPM',   'buy',   10,  269.00, '2026-09-01 14:16:28'),
    ( 5, 2, 'KO',    'buy',   30,   69.23, '2026-09-01 14:23:36'),
    ( 6, 1, 'MSFT',  'buy',    6,  450.14, '2026-09-02 12:25:38'),  -- adds to position
    ( 7, 2, 'KO',    'buy',   29,   69.02, '2026-09-02 13:31:02'),  -- adds to position
    ( 8, 8, 'DIS',   'buy',   34,   98.11, '2026-09-03 09:59:42'),
    ( 9, 5, 'DIS',   'buy',   30,   97.20, '2026-09-08 10:01:51'),
    (10, 2, 'JNJ',   'buy',   10,  162.11, '2026-09-08 10:05:13'),
    (11, 1, 'AAPL',  'buy',   21,  238.03, '2026-09-08 10:12:18'),  -- adds to position
    (12, 4, 'JPM',   'buy',   18,  269.28, '2026-09-08 13:08:25'),  -- adds to position
    (13, 6, 'NVDA',  'buy',   27,  184.17, '2026-09-08 14:18:45'),
    (14, 3, 'CAT',   'buy',   20,  378.25, '2026-09-08 15:44:20'),
    (15, 3, 'CAT',   'sell',   6,  375.98, '2026-09-08 15:52:03'),
    (16, 7, 'COST',  'buy',    3,  906.90, '2026-09-09 11:22:40'),
    (17, 1, 'MSFT',  'sell',  15,  447.45, '2026-09-09 11:40:54'),  -- closes position
    (18, 7, 'COST',  'buy',    4,  903.35, '2026-09-09 13:25:32'),  -- adds to position
    (19, 3, 'COST',  'buy',    4,  898.32, '2026-09-09 13:38:56'),
    (20, 2, 'KO',    'sell',  37,   67.91, '2026-09-09 13:39:36'),
    (21, 3, 'CAT',   'sell',   9,  375.98, '2026-09-09 14:31:01'),
    (22, 3, 'COST',  'buy',    8,  902.02, '2026-09-09 15:27:57'),  -- adds to position
    (23, 4, 'XOM',   'buy',   25,  114.85, '2026-09-10 15:40:39'),
    (24, 5, 'DIS',   'sell',   1,   95.69, '2026-09-10 15:49:47'),
    (25, 5, 'DIS',   'sell',   3,   93.83, '2026-09-11 11:54:45'),
    (26, 5, 'DIS',   'sell',  26,   93.47, '2026-09-11 14:00:30'),  -- closes position
    (27, 1, 'AAPL',  'sell',  34,  236.77, '2026-09-11 14:57:06'),  -- closes position
    (28, 8, 'DIS',   'sell',   6,   93.03, '2026-09-14 13:42:21'),
    (29, 4, 'XOM',   'buy',   28,  121.03, '2026-09-14 14:32:27'),  -- adds to position
    (30, 6, 'GOOGL', 'buy',   27,  169.78, '2026-09-14 14:35:39'),  -- adds to position
    (31, 3, 'CAT',   'sell',   3,  378.02, '2026-09-14 14:55:37'),
    (32, 2, 'KO',    'buy',   29,   67.23, '2026-09-15 10:56:21'),  -- adds to position
    (33, 5, 'KO',    'buy',   37,   66.76, '2026-09-15 11:00:58'),
    (34, 8, 'DIS',   'sell',   7,   91.62, '2026-09-15 15:53:16'),
    (35, 3, 'CAT',   'sell',   1,  376.63, '2026-09-15 15:54:38'),
    (36, 8, 'DIS',   'sell',  18,   91.69, '2026-09-16 09:36:05'),
    (37, 6, 'NVDA',  'buy',   27,  173.39, '2026-09-16 09:39:58'),  -- adds to position
    (38, 1, 'MSFT',  'buy',   11,  451.87, '2026-09-16 11:57:05'),
    (39, 4, 'CAT',   'buy',    6,  381.67, '2026-09-16 12:56:14'),
    (40, 1, 'GOOGL', 'buy',   24,  172.52, '2026-09-16 14:13:09'),
    (41, 8, 'DIS',   'sell',   3,   90.00, '2026-09-16 14:21:59'),  -- closes position
    (42, 4, 'XOM',   'buy',   32,  119.94, '2026-09-16 14:28:26'),  -- adds to position
    (43, 1, 'NVDA',  'buy',   33,  175.86, '2026-09-16 15:21:41'),
    (44, 4, 'CAT',   'buy',    8,  387.19, '2026-09-17 09:39:41'),  -- adds to position
    (45, 8, 'AAPL',  'buy',   13,  237.40, '2026-09-17 10:33:16'),
    (46, 5, 'AAPL',  'buy',    4,  236.88, '2026-09-17 11:02:43'),
    (47, 3, 'COST',  'sell',   3,  923.51, '2026-09-17 12:26:58'),
    (48, 3, 'CAT',   'buy',   11,  384.86, '2026-09-17 12:39:35'),  -- adds to position
    (49, 3, 'CAT',   'sell',  12,  387.33, '2026-09-17 13:35:46'),  -- closes position
    (50, 3, 'COST',  'sell',   9,  921.74, '2026-09-17 15:51:00'),  -- closes position
    (51, 6, 'GOOGL', 'buy',   32,  172.67, '2026-09-18 12:37:19'),  -- adds to position
    (52, 1, 'GOOGL', 'buy',   19,  170.90, '2026-09-18 14:48:52'),  -- adds to position
    (53, 6, 'AMZN',  'buy',   22,  200.27, '2026-09-21 10:06:04'),
    (54, 3, 'COST',  'buy',    6,  924.15, '2026-09-21 11:17:47'),
    (55, 3, 'AMZN',  'buy',   33,  199.63, '2026-09-21 12:44:17'),
    (56, 5, 'KO',    'buy',   19,   66.64, '2026-09-21 13:43:22'),  -- adds to position
    (57, 7, 'KO',    'buy',   33,   66.76, '2026-09-21 13:47:22'),
    (58, 6, 'NVDA',  'buy',   41,  170.01, '2026-09-21 14:02:53'),  -- adds to position
    (59, 1, 'NVDA',  'sell',   8,  169.46, '2026-09-21 14:12:47'),
    (60, 5, 'AAPL',  'buy',    8,  230.03, '2026-09-22 11:32:17'),  -- adds to position
    (61, 5, 'COST',  'buy',    2,  918.83, '2026-09-22 12:36:41'),
    (62, 1, 'AAPL',  'buy',    9,  231.95, '2026-09-23 09:58:25'),
    (63, 6, 'GOOGL', 'buy',   20,  175.72, '2026-09-23 10:44:43'),  -- adds to position
    (64, 3, 'NVDA',  'buy',   40,  182.94, '2026-09-23 13:35:27'),
    (65, 3, 'NVDA',  'buy',   27,  183.31, '2026-09-23 14:23:17'),  -- adds to position
    (66, 7, 'KO',    'buy',   51,   66.64, '2026-09-24 11:00:21'),  -- adds to position
    (67, 4, 'JPM',   'sell',  28,  267.33, '2026-09-24 12:00:17'),  -- closes position
    (68, 2, 'KO',    'sell',  51,   66.45, '2026-09-24 12:18:34'),  -- closes position
    (69, 2, 'JNJ',   'buy',   15,  165.37, '2026-09-24 12:50:19'),  -- adds to position
    (70, 4, 'JPM',   'buy',    8,  264.90, '2026-09-25 10:17:44'),
    (71, 1, 'GOOGL', 'buy',   31,  177.71, '2026-09-25 10:25:42'),  -- adds to position
    (72, 2, 'JNJ',   'buy',   12,  163.69, '2026-09-25 12:51:24'),  -- adds to position
    (73, 3, 'COST',  'buy',    7,  929.28, '2026-09-25 13:07:57'),  -- adds to position
    (74, 5, 'COST',  'buy',    3,  927.65, '2026-09-25 14:32:17'),  -- adds to position
    (75, 1, 'AAPL',  'sell',   7,  219.01, '2026-09-25 15:54:08'),
    (76, 8, 'AAPL',  'buy',   20,  218.77, '2026-09-25 15:56:50'),  -- adds to position
    (77, 8, 'DIS',   'buy',   28,   89.45, '2026-09-28 10:46:43'),
    (78, 6, 'AMZN',  'buy',   38,  194.33, '2026-09-28 11:26:31'),  -- adds to position
    (79, 6, 'AMZN',  'sell',  31,  194.62, '2026-09-28 13:22:56'),
    (80, 6, 'NVDA',  'sell',  76,  174.49, '2026-09-28 13:57:37'),
    (81, 3, 'NVDA',  'sell',  25,  174.56, '2026-09-28 14:05:56'),
    (82, 3, 'DIS',   'buy',   42,   89.34, '2026-09-28 15:44:01');

-- -----------------------------------------------------
-- holds (derived from `transaction`, see header)
-- -----------------------------------------------------
INSERT INTO `holds` (`user_id`, `ticker`, `quantity`, `average_price`) VALUES
    (1, 'AAPL',    2,  231.9500),
    (1, 'GOOGL',  74,  174.2782),
    (1, 'MSFT',   11,  451.8700),
    (1, 'NVDA',   25,  175.8600),
    (2, 'JNJ',    37,  163.9441),
    (3, 'AMZN',   33,  199.6300),
    (3, 'COST',   13,  926.9123),
    (3, 'DIS',    42,   89.3400),
    (3, 'NVDA',   42,  183.0891),
    (4, 'CAT',    14,  384.8243),
    (4, 'JPM',     8,  264.9000),
    (4, 'XOM',    85,  118.8020),
    (5, 'AAPL',   12,  232.3133),
    (5, 'COST',    5,  924.1220),
    (5, 'KO',     56,   66.7193),
    (6, 'AMZN',   29,  196.5080),
    (6, 'GOOGL', 117,  175.4021),
    (6, 'NVDA',   19,  174.9951),
    (7, 'COST',    7,  904.8714),
    (7, 'KO',     84,   66.6871),
    (8, 'AAPL',   33,  226.1091),
    (8, 'DIS',    28,   89.4500);
