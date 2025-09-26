-- Test Database Setup for Strategy Integration
-- Run this before running the integration test

-- Insert a test user for the strategy wallet
INSERT INTO users (wallet_address, email, created_at) 
VALUES ('strategy_wallet', 'strategy@test.com', CURRENT_TIMESTAMP)
ON CONFLICT (wallet_address) DO NOTHING;

-- Insert some sample market data
INSERT INTO market_data (asset_pair, exchange, price, volume, timestamp) 
VALUES 
    ('ALGO/USDC', 'tinyman', 0.125, 50000.0, CURRENT_TIMESTAMP),
    ('ALGO/USDC', 'pact', 0.128, 45000.0, CURRENT_TIMESTAMP),
    ('ALGO/STBL', 'tinyman', 0.126, 30000.0, CURRENT_TIMESTAMP),
    ('ALGO/STBL', 'algofi', 0.122, 35000.0, CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;