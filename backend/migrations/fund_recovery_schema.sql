-- Emergency Fund Recovery Database Schema
-- This schema supports the fund recovery and security system

-- Manual recovery requests table for emergency situations
CREATE TABLE IF NOT EXISTS manual_recovery_requests (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) NOT NULL,
    investment_id BIGINT,
    protocol_name VARCHAR(50) NOT NULL,
    amount BIGINT NOT NULL, -- Amount in microALGO
    request_type VARCHAR(20) NOT NULL DEFAULT 'emergency_recovery', -- 'emergency_recovery', 'time_lock_override', 'protocol_failure'
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- 'pending', 'in_review', 'approved', 'completed', 'rejected'
    priority VARCHAR(10) NOT NULL DEFAULT 'normal', -- 'low', 'normal', 'high', 'critical'
    description TEXT,
    
    -- Recovery details
    original_tx_id VARCHAR(100),
    recovery_tx_id VARCHAR(100),
    recovery_method VARCHAR(50), -- 'standard_withdrawal', 'direct_protocol_call', 'manual_intervention'
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    reviewed_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Staff assignment
    assigned_to VARCHAR(100),
    reviewer_notes TEXT,
    
    -- Technical details
    metadata JSONB DEFAULT '{}',
    
    FOREIGN KEY (wallet_address) REFERENCES users(wallet_address),
    INDEX idx_manual_recovery_wallet (wallet_address),
    INDEX idx_manual_recovery_status (status),
    INDEX idx_manual_recovery_created (created_at),
    INDEX idx_manual_recovery_priority (priority)
);

-- Recovery audit log for tracking all recovery attempts
CREATE TABLE IF NOT EXISTS recovery_audit_log (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(58) NOT NULL,
    investment_id BIGINT,
    action_type VARCHAR(30) NOT NULL, -- 'withdrawal_attempt', 'emergency_request', 'manual_intervention', 'recovery_complete'
    protocol_name VARCHAR(50),
    amount BIGINT,
    
    -- Transaction details
    tx_id VARCHAR(100),
    success BOOLEAN NOT NULL DEFAULT false,
    error_message TEXT,
    
    -- Context
    initiated_by VARCHAR(20) NOT NULL, -- 'user', 'system', 'admin'
    recovery_method VARCHAR(50),
    time_lock_override BOOLEAN DEFAULT false,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    
    INDEX idx_recovery_audit_wallet (wallet_address),
    INDEX idx_recovery_audit_created (created_at),
    INDEX idx_recovery_audit_success (success)
);

-- Protocol health monitoring for early warning
CREATE TABLE IF NOT EXISTS protocol_health_status (
    id SERIAL PRIMARY KEY,
    protocol_name VARCHAR(50) NOT NULL UNIQUE,
    
    -- Health indicators
    is_operational BOOLEAN NOT NULL DEFAULT true,
    liquidity_health VARCHAR(10) NOT NULL DEFAULT 'healthy', -- 'healthy', 'low', 'critical'
    last_successful_transaction TIMESTAMP,
    last_failed_transaction TIMESTAMP,
    
    -- Risk assessment
    current_risk_level VARCHAR(10) NOT NULL DEFAULT 'low', -- 'low', 'medium', 'high', 'critical'
    total_value_locked BIGINT DEFAULT 0,
    withdrawal_delay_average INTEGER DEFAULT 0, -- in seconds
    
    -- Automated flags
    auto_recovery_disabled BOOLEAN DEFAULT false,
    requires_manual_review BOOLEAN DEFAULT false,
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    INDEX idx_protocol_health_name (protocol_name),
    INDEX idx_protocol_health_operational (is_operational),
    INDEX idx_protocol_health_risk (current_risk_level)
);

-- Insert initial protocol health records
INSERT INTO protocol_health_status (protocol_name, current_risk_level, withdrawal_delay_average) VALUES
('tinyman', 'medium', 0),
('algofi', 'low', 86400),
('pact', 'high', 604800)
ON CONFLICT (protocol_name) DO NOTHING;

-- User recovery preferences
CREATE TABLE IF NOT EXISTS user_recovery_preferences (
    wallet_address VARCHAR(58) PRIMARY KEY,
    
    -- Recovery settings
    auto_recovery_enabled BOOLEAN DEFAULT true,
    max_auto_recovery_amount BIGINT DEFAULT 100000000000, -- 100,000 ALGO in microALGO
    emergency_contact_method VARCHAR(20), -- 'email', 'telegram', 'discord'
    emergency_contact_value VARCHAR(200),
    
    -- Risk tolerance
    accept_time_lock_override BOOLEAN DEFAULT false,
    require_manual_approval_above BIGINT DEFAULT 10000000000, -- 10,000 ALGO
    
    -- Notifications
    notify_on_time_lock BOOLEAN DEFAULT true,
    notify_on_protocol_issues BOOLEAN DEFAULT true,
    
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    FOREIGN KEY (wallet_address) REFERENCES users(wallet_address)
);

-- Create triggers for updating timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_manual_recovery_updated_at BEFORE UPDATE ON manual_recovery_requests 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_protocol_health_updated_at BEFORE UPDATE ON protocol_health_status 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_recovery_preferences_updated_at BEFORE UPDATE ON user_recovery_preferences 
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE manual_recovery_requests IS 'Emergency fund recovery requests requiring manual review';
COMMENT ON TABLE recovery_audit_log IS 'Complete audit trail of all recovery attempts and outcomes';
COMMENT ON TABLE protocol_health_status IS 'Real-time health monitoring of DeFi protocols';
COMMENT ON TABLE user_recovery_preferences IS 'User-specific recovery and notification preferences';

COMMENT ON COLUMN manual_recovery_requests.priority IS 'Recovery request priority: critical = <24h, high = <3 days, normal = <1 week';
COMMENT ON COLUMN protocol_health_status.liquidity_health IS 'Protocol liquidity status affects recovery success probability';
COMMENT ON COLUMN user_recovery_preferences.max_auto_recovery_amount IS 'Maximum amount for automated recovery without manual review';