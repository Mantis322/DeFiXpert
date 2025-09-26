"""
Strategy Execution Engine
Manages and executes multiple trading strategies with risk controls
"""

using Dates
include("TradingStrategyFramework.jl")
include("ArbitrageStrategy.jl")
include("YieldFarmingStrategy.jl")

mutable struct StrategyExecutionEngine
    strategies::Dict{Int, TradingStrategy}
    active_opportunities::Vector{TradingOpportunity}
    execution_history::Vector{TradeResult}
    risk_limits::Dict{String, Float64}
    total_allocated_capital::Float64
    max_daily_trades::Int
    daily_trade_count::Int
    last_reset_date::Date
    
    function StrategyExecutionEngine(total_capital::Float64 = 10000.0)
        new(
            Dict{Int, TradingStrategy}(),
            TradingOpportunity[],
            TradeResult[],
            Dict{String, Float64}(
                "max_daily_loss" => total_capital * 0.02,  # 2% max daily loss
                "max_position_size" => total_capital * 0.1,  # 10% max per position
                "max_correlation" => 0.7,  # Max correlation between strategies
                "min_liquidity" => 1000.0  # Minimum liquidity requirement
            ),
            total_capital,
            50,  # Max 50 trades per day
            0,
            today()
        )
    end
end

function register_strategy!(engine::StrategyExecutionEngine, strategy_id::Int, strategy::TradingStrategy)
    engine.strategies[strategy_id] = strategy
    @info "Strategy registered: ID $strategy_id, Type: $(typeof(strategy))"
end

function unregister_strategy!(engine::StrategyExecutionEngine, strategy_id::Int)
    if haskey(engine.strategies, strategy_id)
        cleanup!(engine.strategies[strategy_id])
        delete!(engine.strategies, strategy_id)
        @info "Strategy unregistered: ID $strategy_id"
    end
end

function reset_daily_counters!(engine::StrategyExecutionEngine)
    if today() > engine.last_reset_date
        engine.daily_trade_count = 0
        engine.last_reset_date = today()
        
        # Calculate daily P&L
        today_trades = filter(t -> Date(t.timestamp) == today(), engine.execution_history)
        daily_pnl = sum(t.actual_profit for t in today_trades)
        
        @info "Daily reset: Trades: $(length(today_trades)), P&L: $daily_pnl"
    end
end

function check_risk_limits(engine::StrategyExecutionEngine, opportunity::TradingOpportunity)::Bool
    # Check daily trade limit
    if engine.daily_trade_count >= engine.max_daily_trades
        @warn "Daily trade limit exceeded"
        return false
    end
    
    # Check position size limit
    if opportunity.required_capital > engine.risk_limits["max_position_size"]
        @warn "Position size exceeds limit: $(opportunity.required_capital)"
        return false
    end
    
    # Check available capital
    allocated_capital = sum(s.config.allocated_amount for s in values(engine.strategies))
    if allocated_capital + opportunity.required_capital > engine.total_allocated_capital
        @warn "Insufficient available capital"
        return false
    end
    
    # Check daily loss limit
    today_trades = filter(t -> Date(t.timestamp) == today(), engine.execution_history)
    daily_pnl = sum(t.actual_profit for t in today_trades)
    
    if daily_pnl < -engine.risk_limits["max_daily_loss"]
        @warn "Daily loss limit exceeded: $daily_pnl"
        return false
    end
    
    return true
end

function scan_all_opportunities!(engine::StrategyExecutionEngine, market_data::Vector{MarketData})
    reset_daily_counters!(engine)
    empty!(engine.active_opportunities)
    
    # Collect opportunities from all active strategies
    for (strategy_id, strategy) in engine.strategies
        if strategy.config.is_active
            try
                opportunities = scan_opportunities(strategy, market_data)
                for opp in opportunities
                    opp.strategy_id = strategy_id  # Ensure correct strategy ID
                    push!(engine.active_opportunities, opp)
                end
            catch e
                @error "Error scanning opportunities for strategy $strategy_id: $e"
            end
        end
    end
    
    # Sort opportunities by expected profit and confidence
    sort!(engine.active_opportunities, 
          by = opp -> opp.expected_profit * opp.confidence_score, 
          rev = true)
    
    @info "Scanned $(length(engine.active_opportunities)) opportunities from $(length(engine.strategies)) strategies"
end

function execute_top_opportunities!(engine::StrategyExecutionEngine, max_executions::Int = 5)
    executed_count = 0
    
    for opportunity in engine.active_opportunities
        if executed_count >= max_executions
            break
        end
        
        # Check if we should execute this opportunity
        strategy = engine.strategies[opportunity.strategy_id]
        
        if !should_execute(strategy, opportunity)
            continue
        end
        
        # Apply risk checks
        if !check_risk_limits(engine, opportunity)
            continue
        end
        
        # Execute the trade
        @info "Executing opportunity: $(opportunity.opportunity_type) for $(opportunity.asset_pair)"
        
        result = execute_trade(strategy, opportunity)
        push!(engine.execution_history, result)
        
        if result.success
            engine.daily_trade_count += 1
            executed_count += 1
            
            @info "Trade executed successfully: Profit=$(result.actual_profit), Hash=$(result.transaction_hash)"
        else
            @error "Trade execution failed: $(result.error_message)"
        end
        
        # Brief pause between executions
        sleep(0.1)
    end
    
    return executed_count
end

function get_strategy_performance(engine::StrategyExecutionEngine, strategy_id::Int, days::Int = 30)::Dict{String, Any}
    cutoff_date = now() - Day(days)
    strategy_trades = filter(t -> t.timestamp >= cutoff_date, engine.execution_history)
    
    # Filter by strategy if we had strategy tracking in trade results
    total_trades = length(strategy_trades)
    successful_trades = length(filter(t -> t.success, strategy_trades))
    total_profit = sum(t.actual_profit for t in strategy_trades)
    total_volume = sum(t.executed_amount for t in strategy_trades)
    avg_execution_time = total_trades > 0 ? mean(t.execution_time_ms for t in strategy_trades) : 0
    
    return Dict{String, Any}(
        "strategy_id" => strategy_id,
        "period_days" => days,
        "total_trades" => total_trades,
        "successful_trades" => successful_trades,
        "success_rate" => total_trades > 0 ? successful_trades / total_trades : 0.0,
        "total_profit" => total_profit,
        "total_volume" => total_volume,
        "avg_execution_time_ms" => avg_execution_time,
        "profit_per_trade" => total_trades > 0 ? total_profit / total_trades : 0.0
    )
end

function get_engine_status(engine::StrategyExecutionEngine)::Dict{String, Any}
    active_strategies = length(filter(s -> s.config.is_active, values(engine.strategies)))
    total_allocated = sum(s.config.allocated_amount for s in values(engine.strategies))
    available_capital = engine.total_allocated_capital - total_allocated
    
    # Recent performance
    recent_trades = filter(t -> t.timestamp >= now() - Hour(24), engine.execution_history)
    recent_profit = sum(t.actual_profit for t in recent_trades)
    
    return Dict{String, Any}(
        "total_strategies" => length(engine.strategies),
        "active_strategies" => active_strategies,
        "total_capital" => engine.total_allocated_capital,
        "allocated_capital" => total_allocated,
        "available_capital" => available_capital,
        "daily_trades" => engine.daily_trade_count,
        "max_daily_trades" => engine.max_daily_trades,
        "active_opportunities" => length(engine.active_opportunities),
        "recent_24h_trades" => length(recent_trades),
        "recent_24h_profit" => recent_profit,
        "last_scan" => length(engine.active_opportunities) > 0 ? engine.active_opportunities[1].detected_at : nothing
    )
end

# Utility function to create strategy instances
function create_strategy(strategy_type::String)::Union{TradingStrategy, Nothing}
    if strategy_type == "arbitrage"
        return ArbitrageStrategy()
    elseif strategy_type == "yield_farming"
        return YieldFarmingStrategy()
    else
        @error "Unknown strategy type: $strategy_type"
        return nothing
    end
end

export StrategyExecutionEngine, register_strategy!, unregister_strategy!
export scan_all_opportunities!, execute_top_opportunities!, get_strategy_performance
export get_engine_status, create_strategy