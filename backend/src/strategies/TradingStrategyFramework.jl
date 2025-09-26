"""
Trading Strategy Framework for AlgoFi
Base classes and interfaces for implementing algorithmic trading strategies
"""

using Dates
using JSON3

# Abstract base class for all trading strategies
abstract type TradingStrategy end

# Strategy configuration structure
Base.@kwdef mutable struct StrategyConfig
    id::Union{Int, Nothing} = nothing
    name::String
    strategy_type::String
    is_active::Bool = false
    allocated_amount::Float64 = 0.0
    max_position_size::Float64 = 1000.0
    stop_loss_pct::Float64 = 0.05  # 5% stop loss
    take_profit_pct::Float64 = 0.10  # 10% take profit
    max_slippage_pct::Float64 = 0.01  # 1% max slippage
    min_profit_threshold::Float64 = 0.001  # Minimum profit to execute
    created_at::DateTime = now()
    settings::Dict{String, Any} = Dict{String, Any}()
end

# Market data structure
Base.@kwdef struct MarketData
    asset_id::String
    price::Float64
    volume_24h::Float64
    spread::Float64
    liquidity::Float64
    timestamp::DateTime = now()
end

# Trading opportunity structure
Base.@kwdef struct TradingOpportunity
    strategy_id::Int
    opportunity_type::String  # "arbitrage", "yield", "market_making"
    asset_pair::String
    expected_profit::Float64
    confidence_score::Float64
    execution_time_ms::Int
    required_capital::Float64
    metadata::Dict{String, Any} = Dict{String, Any}()
    detected_at::DateTime = now()
end

# Trade execution result
Base.@kwdef struct TradeResult
    success::Bool
    transaction_hash::Union{String, Nothing} = nothing
    executed_amount::Float64 = 0.0
    actual_profit::Float64 = 0.0
    gas_cost::Float64 = 0.0
    slippage::Float64 = 0.0
    execution_time_ms::Int = 0
    error_message::Union{String, Nothing} = nothing
    timestamp::DateTime = now()
end

# Required interface methods for all strategies
function initialize!(strategy::TradingStrategy, config::StrategyConfig) end
function scan_opportunities(strategy::TradingStrategy, market_data::Vector{MarketData})::Vector{TradingOpportunity} end
function execute_trade(strategy::TradingStrategy, opportunity::TradingOpportunity)::TradeResult end
function calculate_position_size(strategy::TradingStrategy, opportunity::TradingOpportunity)::Float64 end
function should_execute(strategy::TradingStrategy, opportunity::TradingOpportunity)::Bool end
function cleanup!(strategy::TradingStrategy) end

# Risk management functions
function calculate_risk_score(opportunity::TradingOpportunity, config::StrategyConfig)::Float64
    risk_factors = [
        opportunity.confidence_score < 0.7 ? 0.3 : 0.0,
        opportunity.required_capital > config.max_position_size ? 0.4 : 0.0,
        opportunity.expected_profit < config.min_profit_threshold ? 0.2 : 0.0
    ]
    return sum(risk_factors)
end

function validate_opportunity(opportunity::TradingOpportunity, config::StrategyConfig)::Bool
    risk_score = calculate_risk_score(opportunity, config)
    return risk_score < 0.5 && opportunity.expected_profit > config.min_profit_threshold
end

# Utility functions
function format_asset_pair(asset_a::String, asset_b::String)::String
    return "$asset_a/$asset_b"
end

function calculate_slippage(expected_price::Float64, actual_price::Float64)::Float64
    return abs(actual_price - expected_price) / expected_price
end

function log_strategy_event(strategy_name::String, event::String, data::Dict{String, Any})
    timestamp = now()
    log_entry = Dict(
        "timestamp" => timestamp,
        "strategy" => strategy_name,
        "event" => event,
        "data" => data
    )
    @info "Strategy Event: $(JSON3.write(log_entry))"
end

export TradingStrategy, StrategyConfig, MarketData, TradingOpportunity, TradeResult
export initialize!, scan_opportunities, execute_trade, calculate_position_size, should_execute, cleanup!
export calculate_risk_score, validate_opportunity, format_asset_pair, calculate_slippage, log_strategy_event