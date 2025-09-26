CREATE TYPE agent_state as ENUM (
    'CREATED',
    'RUNNING',
    'PAUSED',
    'STOPPED'
);

CREATE TYPE trigger_type as ENUM (
    'WEBHOOK',
    'PERIODIC'
);

CREATE TABLE agents (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    strategy TEXT NOT NULL,
    strategy_config JSONB,
    trigger_type trigger_type NOT NULL,
    trigger_params JSONB,
    state agent_state NOT NULL DEFAULT 'CREATED'
);

CREATE TABLE agent_tools (
    agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tool_index INT NOT NULL,
    tool_name TEXT NOT NULL,
    tool_config JSONB,
    PRIMARY KEY (agent_id, tool_index)
);

-- Table for real-time market data
CREATE TABLE market_data (
    id SERIAL PRIMARY KEY,
    asset_id TEXT NOT NULL,
    asset_name TEXT NOT NULL,
    exchange TEXT NOT NULL,
    price DECIMAL(20,8) NOT NULL,
    volume_24h DECIMAL(20,8),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(asset_id, exchange, timestamp)
);

-- Table for trading strategies execution events
CREATE TABLE strategy_events (
    id SERIAL PRIMARY KEY,
    strategy_name TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_data JSONB,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Table for AI swarm management
CREATE TABLE swarm_configs (
    id SERIAL PRIMARY KEY,
    config_name TEXT UNIQUE NOT NULL,
    population_size INTEGER DEFAULT 20,
    inertia_weight DECIMAL(5,3) DEFAULT 0.5,
    cognitive_coeff DECIMAL(5,3) DEFAULT 1.5,
    social_coeff DECIMAL(5,3) DEFAULT 1.5,
    max_iterations INTEGER DEFAULT 100,
    convergence_threshold DECIMAL(10,6) DEFAULT 0.001,
    risk_tolerance DECIMAL(5,3) DEFAULT 0.3,
    auto_optimize BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table for individual swarm agents
CREATE TABLE swarm_agents (
    id SERIAL PRIMARY KEY,
    agent_name TEXT NOT NULL,
    strategy_type TEXT NOT NULL,
    profit DECIMAL(15,8) DEFAULT 0.0,
    success_rate DECIMAL(5,2) DEFAULT 0.0,
    status TEXT CHECK (status IN ('active', 'paused', 'optimizing', 'stopped')) DEFAULT 'active',
    fitness DECIMAL(10,6) DEFAULT 0.0,
    position_x DECIMAL(8,4) DEFAULT 0.0,
    position_y DECIMAL(8,4) DEFAULT 0.0,
    config_data JSONB,
    last_update TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(agent_name)
);

-- Table for swarm performance metrics
CREATE TABLE swarm_metrics (
    id SERIAL PRIMARY KEY,
    agent_id INTEGER REFERENCES swarm_agents(id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL, -- 'profit', 'success_rate', 'risk_score', etc.
    metric_value DECIMAL(15,8) NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for better performance
CREATE INDEX idx_swarm_agents_status ON swarm_agents(status);
CREATE INDEX idx_swarm_agents_strategy ON swarm_agents(strategy_type);
CREATE INDEX idx_swarm_metrics_agent_time ON swarm_metrics(agent_id, recorded_at);
CREATE INDEX idx_market_data_timestamp ON market_data(timestamp);
CREATE INDEX idx_strategy_events_timestamp ON strategy_events(timestamp);