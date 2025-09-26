-- AlgoFi AI Swarm Platform - User-based Database Schema
-- This schema extends the existing agent system with user management and trading features

-- User wallet addresses and profiles
CREATE TABLE users (
    wallet_address TEXT PRIMARY KEY,
    firebase_uid TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP,
    account_info JSONB, -- Algorand account information
    settings JSONB DEFAULT '{
        "riskLevel": "medium",
        "maxInvestment": 1000,
        "autoTrading": false,
        "notifications": true
    }'::jsonb,
    is_active BOOLEAN DEFAULT true
);

-- User performance tracking
CREATE TABLE user_performance (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_invested DECIMAL(20, 6) DEFAULT 0,
    total_profit DECIMAL(20, 6) DEFAULT 0,
    total_trades INTEGER DEFAULT 0,
    successful_trades INTEGER DEFAULT 0,
    daily_profit DECIMAL(20, 6) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(wallet_address, date)
);

-- Trading strategies per user
CREATE TABLE user_strategies (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    strategy_name TEXT NOT NULL,
    strategy_type TEXT NOT NULL, -- 'yield_farming', 'arbitrage', 'liquidity_providing'
    parameters JSONB NOT NULL,
    allocation DECIMAL(5, 2) NOT NULL DEFAULT 0.00, -- Percentage allocation
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- AI Agent assignments per user
CREATE TABLE user_agents (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT true,
    assignment_date TIMESTAMP DEFAULT NOW(),
    parameters JSONB,
    UNIQUE(wallet_address, agent_id)
);

-- Trading transactions log
CREATE TABLE trading_transactions (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    transaction_id TEXT NOT NULL UNIQUE, -- Algorand transaction ID
    strategy_id INTEGER REFERENCES user_strategies(id),
    transaction_type TEXT NOT NULL, -- 'buy', 'sell', 'swap', 'stake', 'unstake'
    asset_from TEXT,
    asset_to TEXT,
    amount_from DECIMAL(20, 6),
    amount_to DECIMAL(20, 6),
    price DECIMAL(20, 6),
    fee DECIMAL(20, 6),
    profit_loss DECIMAL(20, 6),
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'confirmed', 'failed'
    executed_at TIMESTAMP DEFAULT NOW(),
    confirmed_at TIMESTAMP
);

-- Portfolio snapshots
CREATE TABLE portfolio_snapshots (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    snapshot_date TIMESTAMP DEFAULT NOW(),
    total_value_usd DECIMAL(20, 6),
    total_algo DECIMAL(20, 6),
    assets JSONB, -- Asset breakdown
    performance_metrics JSONB, -- Daily/weekly/monthly returns, Sharpe ratio, etc.
    created_at TIMESTAMP DEFAULT NOW()
);

-- Market data cache
CREATE TABLE market_data (
    id SERIAL PRIMARY KEY,
    symbol TEXT NOT NULL,
    price_usd DECIMAL(20, 6),
    price_algo DECIMAL(20, 6),
    volume_24h DECIMAL(20, 6),
    change_24h DECIMAL(10, 6),
    market_cap DECIMAL(20, 6),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(symbol, DATE(updated_at))
);

-- Arbitrage opportunities
CREATE TABLE arbitrage_opportunities (
    id SERIAL PRIMARY KEY,
    pair TEXT NOT NULL, -- e.g., 'ALGO/USDC'
    dex_from TEXT NOT NULL,
    dex_to TEXT NOT NULL,
    price_from DECIMAL(20, 6),
    price_to DECIMAL(20, 6),
    spread DECIMAL(10, 6),
    estimated_profit DECIMAL(20, 6),
    confidence DECIMAL(3, 2), -- 0.00 to 1.00
    detected_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    status TEXT DEFAULT 'active' -- 'active', 'expired', 'executed'
);

-- System notifications
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    wallet_address TEXT NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'info', -- 'info', 'success', 'warning', 'error'
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX idx_user_performance_wallet_date ON user_performance(wallet_address, date DESC);
CREATE INDEX idx_user_strategies_wallet ON user_strategies(wallet_address);
CREATE INDEX idx_trading_transactions_wallet ON trading_transactions(wallet_address);
CREATE INDEX idx_trading_transactions_date ON trading_transactions(executed_at DESC);
CREATE INDEX idx_portfolio_snapshots_wallet_date ON portfolio_snapshots(wallet_address, snapshot_date DESC);
CREATE INDEX idx_market_data_symbol_date ON market_data(symbol, updated_at DESC);
CREATE INDEX idx_arbitrage_opportunities_status ON arbitrage_opportunities(status, detected_at DESC);
CREATE INDEX idx_notifications_wallet_read ON notifications(wallet_address, is_read, created_at DESC);

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply update triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_strategies_updated_at BEFORE UPDATE ON user_strategies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();