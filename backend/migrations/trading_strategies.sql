-- Additional tables for AlgoFi trading platform

-- Users table (if not exists)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE,
    settings JSONB DEFAULT '{}',
    account_info JSONB DEFAULT '{}'
);

-- Trading strategies table
CREATE TABLE IF NOT EXISTS strategies (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    strategy_name VARCHAR(255) NOT NULL,
    strategy_type VARCHAR(50) NOT NULL CHECK (strategy_type IN ('arbitrage', 'yield_farming', 'market_making')),
    allocated_amount DECIMAL(20, 6) DEFAULT 0,
    is_active BOOLEAN DEFAULT FALSE,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_strategy_name_per_user UNIQUE (user_id, strategy_name)
);

-- Strategy performance tracking
CREATE TABLE IF NOT EXISTS strategy_performance (
    id SERIAL PRIMARY KEY,
    strategy_id INTEGER REFERENCES strategies(id) ON DELETE CASCADE,
    pnl DECIMAL(20, 6) DEFAULT 0,
    performance_score DECIMAL(4, 3) DEFAULT 0.5 CHECK (performance_score >= 0 AND performance_score <= 1),
    trades_count INTEGER DEFAULT 0,
    successful_trades INTEGER DEFAULT 0,
    total_volume DECIMAL(20, 6) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trading transactions
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    strategy_id INTEGER REFERENCES strategies(id) ON DELETE CASCADE,
    transaction_hash VARCHAR(255),
    transaction_type VARCHAR(50) NOT NULL,
    amount DECIMAL(20, 6) NOT NULL,
    asset_id VARCHAR(20),
    price DECIMAL(20, 6),
    fee DECIMAL(20, 6) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    confirmed_at TIMESTAMP WITH TIME ZONE
);

-- Market data cache (for strategy optimization)
CREATE TABLE IF NOT EXISTS market_data (
    id SERIAL PRIMARY KEY,
    asset_pair VARCHAR(20) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    price DECIMAL(20, 6) NOT NULL,
    volume_24h DECIMAL(20, 6) DEFAULT 0,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_pair_exchange_time UNIQUE (asset_pair, exchange, timestamp)
);

-- Arbitrage opportunities log
CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
    id SERIAL PRIMARY KEY,
    asset_pair VARCHAR(20) NOT NULL,
    exchange_buy VARCHAR(50) NOT NULL,
    exchange_sell VARCHAR(50) NOT NULL,
    price_buy DECIMAL(20, 6) NOT NULL,
    price_sell DECIMAL(20, 6) NOT NULL,
    spread_pct DECIMAL(6, 3) NOT NULL,
    potential_profit DECIMAL(20, 6) NOT NULL,
    status VARCHAR(20) DEFAULT 'detected',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE
);

-- Portfolio snapshots for users
CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    total_balance DECIMAL(20, 6) NOT NULL,
    asset_breakdown JSONB DEFAULT '{}',
    strategy_breakdown JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_strategies_user_active ON strategies(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_strategy_performance_strategy ON strategy_performance(strategy_id);
CREATE INDEX IF NOT EXISTS idx_transactions_user_strategy ON transactions(user_id, strategy_id);
CREATE INDEX IF NOT EXISTS idx_market_data_timestamp ON market_data(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_arbitrage_opportunities_created ON arbitrage_opportunities(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_portfolio_snapshots_user_time ON portfolio_snapshots(user_id, created_at DESC);

-- Functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for automatic timestamp updates
DROP TRIGGER IF EXISTS update_strategies_modtime ON strategies;
CREATE TRIGGER update_strategies_modtime
    BEFORE UPDATE ON strategies
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_column();

-- Sample data for development/testing
INSERT INTO users (wallet_address, settings) VALUES 
('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '{"demo": true}')
ON CONFLICT (wallet_address) DO NOTHING;

INSERT INTO strategies (user_id, strategy_name, strategy_type, allocated_amount, is_active, settings) 
SELECT u.id, 'Demo Arbitrage', 'arbitrage', 500.0, false, '{"min_spread_pct": 0.5, "max_position_size": 1000}'
FROM users u WHERE u.wallet_address = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
ON CONFLICT (user_id, strategy_name) DO NOTHING;

INSERT INTO strategies (user_id, strategy_name, strategy_type, allocated_amount, is_active, settings) 
SELECT u.id, 'Demo Yield Farming', 'yield_farming', 1000.0, false, '{"target_apy": 15, "max_pools": 5}'
FROM users u WHERE u.wallet_address = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
ON CONFLICT (user_id, strategy_name) DO NOTHING;