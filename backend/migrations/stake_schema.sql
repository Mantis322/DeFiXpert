-- Kullanıcı yatırım bilgileri tablosu
CREATE TABLE user_investments (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(100) NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    staked_amount BIGINT NOT NULL DEFAULT 0, -- microAlgos cinsinden
    available_balance BIGINT NOT NULL DEFAULT 0, -- çekilebilir miktar
    total_earnings BIGINT NOT NULL DEFAULT 0, -- toplam kazanç
    ai_strategy_id INTEGER, -- hangi AI stratejisiyle yatırım yapılacak
    stake_status VARCHAR(20) DEFAULT 'active', -- active, withdrawn, paused
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Transaction geçmişi tablosu
CREATE TABLE transaction_history (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(100) NOT NULL REFERENCES users(wallet_address) ON DELETE CASCADE,
    investment_id INTEGER REFERENCES user_investments(id) ON DELETE CASCADE,
    transaction_type VARCHAR(20) NOT NULL, -- stake, withdraw, profit, loss
    amount BIGINT NOT NULL, -- microAlgos cinsinden
    algorand_tx_id VARCHAR(100), -- gerçek Algorand transaction ID
    status VARCHAR(20) DEFAULT 'pending', -- pending, confirmed, failed
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP NULL
);

-- Stake yapılandırma ayarları
CREATE TABLE stake_configs (
    id SERIAL PRIMARY KEY,
    min_stake_amount BIGINT DEFAULT 1000000, -- minimum 1 ALGO (1M microAlgos)
    max_stake_amount BIGINT DEFAULT 1000000000000, -- maximum 1M ALGO
    daily_interest_rate DECIMAL(10,6) DEFAULT 0.001, -- %0.1 günlük faiz
    withdrawal_fee_percentage DECIMAL(5,4) DEFAULT 0.005, -- %0.5 çekim ücreti
    ai_profit_share_percentage DECIMAL(5,4) DEFAULT 0.7, -- AI kazancının %70'i kullanıcıya
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- AI strateji performans tablosu
CREATE TABLE ai_strategy_performance (
    id SERIAL PRIMARY KEY,
    strategy_name VARCHAR(100) NOT NULL,
    total_managed_amount BIGINT DEFAULT 0,
    daily_return_percentage DECIMAL(10,6) DEFAULT 0,
    weekly_return_percentage DECIMAL(10,6) DEFAULT 0,
    monthly_return_percentage DECIMAL(10,6) DEFAULT 0,
    success_rate DECIMAL(5,4) DEFAULT 0, -- başarı oranı
    risk_level VARCHAR(20) DEFAULT 'medium', -- low, medium, high
    active_investors_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- İndeksler
CREATE INDEX idx_user_investments_wallet ON user_investments(wallet_address);
CREATE INDEX idx_user_investments_status ON user_investments(stake_status);
CREATE INDEX idx_transaction_history_wallet ON transaction_history(wallet_address);
CREATE INDEX idx_transaction_history_type ON transaction_history(transaction_type);
CREATE INDEX idx_transaction_history_status ON transaction_history(status);

-- Başlangıç yapılandırması
INSERT INTO stake_configs (min_stake_amount, max_stake_amount, daily_interest_rate) 
VALUES (1000000, 1000000000000, 0.001);

-- Örnek AI stratejileri
INSERT INTO ai_strategy_performance (strategy_name, risk_level) VALUES 
('Conservative Arbitrage', 'low'),
('Dynamic Swarm Trading', 'medium'),
('Aggressive Profit Hunter', 'high');