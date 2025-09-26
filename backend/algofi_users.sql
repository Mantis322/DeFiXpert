-- AlgoFi User Management Database Schema
-- This script creates the necessary tables for user management, performance tracking, and trading operations

-- Drop tables if they exist (for clean reinstall)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS arbitrage_opportunities CASCADE;
DROP TABLE IF EXISTS market_data CASCADE;
DROP TABLE IF EXISTS portfolio_snapshots CASCADE;
DROP TABLE IF EXISTS trading_transactions CASCADE;
DROP TABLE IF EXISTS user_strategies CASCADE;
DROP TABLE IF EXISTS user_performance CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Create users table
CREATE TABLE users (
    wallet_address VARCHAR(58) PRIMARY KEY, -- Algorand wallet addresses are 58 characters
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    settings JSONB DEFAULT '{}', -- User preferences and bot settings
    is_active BOOLEAN DEFAULT true,
    total_deposited DECIMAL(20, 6) DEFAULT 0.0,
    CONSTRAINT valid_wallet_address CHECK (LENGTH(wallet_address) = 58)
);

-- Create user performance tracking table
CREATE TABLE user_performance (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) REFERENCES users(wallet_address) ON DELETE CASCADE,
    date DATE DEFAULT CURRENT_DATE,
    total_invested_algo DECIMAL(20, 6) DEFAULT 0.0,
    current_value_algo DECIMAL(20, 6) DEFAULT 0.0,
    total_pnl_algo DECIMAL(20, 6) DEFAULT 0.0,
    win_rate DECIMAL(5, 4) DEFAULT 0.0, -- Percentage as decimal (0.0 to 1.0)
    total_trades INTEGER DEFAULT 0,
    successful_trades INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(wallet_address, date)
);

-- Create user strategies table
CREATE TABLE user_strategies (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) REFERENCES users(wallet_address) ON DELETE CASCADE,
    strategy_name VARCHAR(255) NOT NULL,
    strategy_type VARCHAR(100) NOT NULL, -- 'arbitrage', 'yield_farming', 'liquidity_mining', etc.
    allocated_amount DECIMAL(20, 6) DEFAULT 0.0,
    is_active BOOLEAN DEFAULT false,
    risk_level VARCHAR(20) DEFAULT 'medium', -- 'low', 'medium', 'high'
    max_allocation_percentage DECIMAL(5, 2) DEFAULT 50.0,
    current_pnl DECIMAL(20, 6) DEFAULT 0.0,
    performance_score DECIMAL(5, 4) DEFAULT 0.0, -- 0.0 to 1.0
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    settings JSONB DEFAULT '{}' -- Strategy-specific settings
);

-- Create trading transactions table
CREATE TABLE trading_transactions (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) REFERENCES users(wallet_address) ON DELETE CASCADE,
    strategy_id INTEGER REFERENCES user_strategies(id) ON DELETE SET NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'buy', 'sell', 'swap', 'stake', 'unstake'
    asset_id VARCHAR(20), -- Algorand asset ID or 'ALGO'
    amount DECIMAL(20, 6) NOT NULL,
    price DECIMAL(20, 6), -- Price at time of transaction
    pnl_amount DECIMAL(20, 6) DEFAULT 0.0, -- Profit/Loss for this transaction
    transaction_hash VARCHAR(100), -- Algorand transaction ID
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}' -- Additional transaction details
);

-- Create portfolio snapshots table for historical tracking
CREATE TABLE portfolio_snapshots (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) REFERENCES users(wallet_address) ON DELETE CASCADE,
    snapshot_date DATE DEFAULT CURRENT_DATE,
    total_value_algo DECIMAL(20, 6) NOT NULL,
    asset_breakdown JSONB DEFAULT '{}', -- JSON object with asset_id: amount pairs
    strategy_breakdown JSONB DEFAULT '{}', -- JSON object with strategy performance
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(wallet_address, snapshot_date)
);

-- Create market data table for price tracking
CREATE TABLE market_data (
    id SERIAL PRIMARY KEY,
    asset_id VARCHAR(20) NOT NULL, -- 'ALGO' or Algorand asset ID
    asset_name VARCHAR(100),
    price_usd DECIMAL(20, 8) NOT NULL,
    price_algo DECIMAL(20, 8), -- Price in ALGO terms
    volume_24h DECIMAL(20, 6),
    market_cap DECIMAL(20, 2),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(asset_id, timestamp)
);

-- Create arbitrage opportunities table
CREATE TABLE arbitrage_opportunities (
    id SERIAL PRIMARY KEY,
    asset_pair VARCHAR(50) NOT NULL, -- e.g., 'ALGO/USDC'
    dex_1 VARCHAR(50) NOT NULL, -- e.g., 'Tinyman'
    dex_2 VARCHAR(50) NOT NULL, -- e.g., 'Pact'
    price_1 DECIMAL(20, 8) NOT NULL,
    price_2 DECIMAL(20, 8) NOT NULL,
    profit_percentage DECIMAL(8, 4) NOT NULL,
    min_trade_amount DECIMAL(20, 6) DEFAULT 1.0,
    max_trade_amount DECIMAL(20, 6) DEFAULT 1000.0,
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create notifications table
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) REFERENCES users(wallet_address) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'info', -- 'info', 'warning', 'error', 'success'
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for better performance
CREATE INDEX idx_users_last_login ON users(last_login);
CREATE INDEX idx_user_performance_wallet_date ON user_performance(wallet_address, date);
CREATE INDEX idx_user_strategies_wallet_active ON user_strategies(wallet_address, is_active);
CREATE INDEX idx_trading_transactions_wallet_time ON trading_transactions(wallet_address, timestamp);
CREATE INDEX idx_trading_transactions_strategy ON trading_transactions(strategy_id);
CREATE INDEX idx_portfolio_snapshots_wallet_date ON portfolio_snapshots(wallet_address, snapshot_date);
CREATE INDEX idx_market_data_asset_time ON market_data(asset_id, timestamp);
CREATE INDEX idx_arbitrage_opportunities_active ON arbitrage_opportunities(is_active, created_at);
CREATE INDEX idx_notifications_wallet_unread ON notifications(wallet_address, is_read);

-- Create triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_user_strategies_updated_at 
    BEFORE UPDATE ON user_strategies 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert sample data for testing
INSERT INTO users (wallet_address, settings) VALUES 
    ('SAMPLEADDRESS1234567890123456789012345678901234567890123456', '{"riskLevel": "medium", "notifications": true}'),
    ('SAMPLEADDRESS9876543210987654321098765432109876543210987654', '{"riskLevel": "high", "notifications": false}');

INSERT INTO user_performance (wallet_address, total_invested_algo, current_value_algo, total_pnl_algo, win_rate, total_trades, successful_trades) VALUES 
    ('SAMPLEADDRESS1234567890123456789012345678901234567890123456', 1000.0, 1089.5, 89.5, 0.75, 120, 90),
    ('SAMPLEADDRESS9876543210987654321098765432109876543210987654', 500.0, 485.2, -14.8, 0.60, 80, 48);

INSERT INTO user_strategies (wallet_address, strategy_name, strategy_type, allocated_amount, is_active, current_pnl, performance_score) VALUES 
    ('SAMPLEADDRESS1234567890123456789012345678901234567890123456', 'Arbitrage Bot', 'arbitrage', 500.0, true, 25.4, 0.85),
    ('SAMPLEADDRESS1234567890123456789012345678901234567890123456', 'Yield Farming', 'yield_farming', 300.0, true, 18.7, 0.92),
    ('SAMPLEADDRESS9876543210987654321098765432109876543210987654', 'Liquidity Mining', 'liquidity_mining', 200.0, false, -5.2, 0.65);

INSERT INTO market_data (asset_id, asset_name, price_usd, price_algo, volume_24h) VALUES 
    ('ALGO', 'Algorand', 0.35, 1.0, 1500000.0),
    ('31566704', 'USDC', 1.00, 2.86, 800000.0),
    ('465865291', 'STBL', 1.00, 2.86, 300000.0);

-- Print success message
DO $$
BEGIN
    RAISE NOTICE 'AlgoFi user management database schema created successfully!';
    RAISE NOTICE 'Tables created: users, user_performance, user_strategies, trading_transactions, portfolio_snapshots, market_data, arbitrage_opportunities, notifications';
    RAISE NOTICE 'Sample data inserted for testing purposes';
END $$;