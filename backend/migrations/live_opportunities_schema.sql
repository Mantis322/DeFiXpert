-- Live Opportunities & Real-time Tracking Schema
-- Bu dosya canlı arbitraj fırsatları ve real-time P&L tracking için gerekli tabloları oluşturur

-- Arbitrage Opportunities tablosu
CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
    id SERIAL PRIMARY KEY,
    asset_pair VARCHAR(50) NOT NULL,
    dex_1 VARCHAR(50) NOT NULL,
    dex_2 VARCHAR(50) NOT NULL,
    price_1 DECIMAL(18, 8) NOT NULL,
    price_2 DECIMAL(18, 8) NOT NULL,
    profit_percentage DECIMAL(8, 4) NOT NULL,
    min_trade_amount DECIMAL(18, 8) NOT NULL DEFAULT 100,
    max_trade_amount DECIMAL(18, 8) NOT NULL DEFAULT 10000,
    is_active BOOLEAN NOT NULL DEFAULT true,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Strategy Performance Tracking tablosu
CREATE TABLE IF NOT EXISTS strategy_performance_tracking (
    id SERIAL PRIMARY KEY,
    strategy_id INTEGER NOT NULL REFERENCES user_strategies(id) ON DELETE CASCADE,
    wallet_address VARCHAR(58) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    allocated_amount DECIMAL(18, 8) NOT NULL,
    current_value DECIMAL(18, 8) NOT NULL,
    pnl_amount DECIMAL(18, 8) NOT NULL,
    pnl_percentage DECIMAL(8, 4) NOT NULL,
    total_trades INTEGER NOT NULL DEFAULT 0,
    successful_trades INTEGER NOT NULL DEFAULT 0,
    win_rate DECIMAL(5, 2) NOT NULL DEFAULT 0.00
);

-- Strategy Trades tablosu (detaylı trade tracking)
CREATE TABLE IF NOT EXISTS strategy_trades (
    id SERIAL PRIMARY KEY,
    strategy_id INTEGER NOT NULL REFERENCES user_strategies(id) ON DELETE CASCADE,
    wallet_address VARCHAR(58) NOT NULL,
    trade_type VARCHAR(20) NOT NULL, -- 'arbitrage', 'yield_farming', 'market_making'
    asset_pair VARCHAR(50),
    entry_price DECIMAL(18, 8),
    exit_price DECIMAL(18, 8),
    quantity DECIMAL(18, 8) NOT NULL,
    pnl_amount DECIMAL(18, 8) NOT NULL,
    trade_status VARCHAR(20) NOT NULL DEFAULT 'completed', -- 'pending', 'completed', 'failed'
    dex_used VARCHAR(50),
    transaction_hash VARCHAR(100),
    executed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Real-time Price Feed tablosu
CREATE TABLE IF NOT EXISTS price_feeds (
    id SERIAL PRIMARY KEY,
    asset_pair VARCHAR(50) NOT NULL,
    dex_name VARCHAR(50) NOT NULL,
    price DECIMAL(18, 8) NOT NULL,
    volume_24h DECIMAL(18, 8),
    last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(asset_pair, dex_name)
);

-- Index'ler performans için
CREATE INDEX IF NOT EXISTS idx_arbitrage_opportunities_active ON arbitrage_opportunities(is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_arbitrage_opportunities_profit ON arbitrage_opportunities(profit_percentage DESC);
CREATE INDEX IF NOT EXISTS idx_strategy_performance_tracking_strategy ON strategy_performance_tracking(strategy_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_strategy_trades_strategy ON strategy_trades(strategy_id, executed_at);
CREATE INDEX IF NOT EXISTS idx_price_feeds_pair_dex ON price_feeds(asset_pair, dex_name);

-- Sample arbitrage opportunities (test data)
INSERT INTO arbitrage_opportunities (asset_pair, dex_1, dex_2, price_1, price_2, profit_percentage, min_trade_amount, max_trade_amount, expires_at) VALUES
('ALGO/USDC', 'Tinyman', 'Pact', 0.1245, 0.1267, 1.77, 100, 5000, NOW() + INTERVAL '10 minutes'),
('USDC/STBL', 'AlgoFi', 'Vestige', 0.9985, 1.0023, 0.38, 500, 10000, NOW() + INTERVAL '8 minutes'),
('ALGO/USDT', 'Pact', 'Humble', 0.1238, 0.1255, 1.37, 200, 3000, NOW() + INTERVAL '15 minutes'),
('STBL/ALGO', 'Vestige', 'Tinyman', 8.0234, 8.1456, 1.52, 150, 4000, NOW() + INTERVAL '12 minutes')
ON CONFLICT DO NOTHING;

-- Sample price feeds (test data)  
INSERT INTO price_feeds (asset_pair, dex_name, price, volume_24h) VALUES
('ALGO/USDC', 'Tinyman', 0.1245, 125000),
('ALGO/USDC', 'Pact', 0.1267, 98000),
('ALGO/USDC', 'AlgoFi', 0.1251, 156000),
('USDC/STBL', 'AlgoFi', 0.9985, 45000),
('USDC/STBL', 'Vestige', 1.0023, 32000),
('ALGO/USDT', 'Pact', 0.1238, 87000),
('ALGO/USDT', 'Humble', 0.1255, 54000)
ON CONFLICT (asset_pair, dex_name) DO UPDATE SET 
    price = EXCLUDED.price,
    volume_24h = EXCLUDED.volume_24h,
    last_updated = NOW();

COMMIT;