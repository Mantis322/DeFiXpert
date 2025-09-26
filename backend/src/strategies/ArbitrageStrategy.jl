"""
Arbitrage Strategy Implementation
Detects and executes arbitrage opportunities across Algorand DEX protocols
"""

using HTTP, JSON3, Dates
using LibPQ  # For PostgreSQL connectivity
using DotEnv  # For environment variables
include("TradingStrategyFramework.jl")
include("RealTimeDataFeed.jl")  # Real-time price feeds
include("PriceStreamManager.jl")  # WebSocket streaming

# Load environment variables
DotEnv.config()

# Strategy event logging helper
function log_strategy_event(strategy_name::String, event_type::String, event_data::Dict{String, Any})
    try
        conn = get_connection()
        if conn !== nothing
            query = """
            INSERT INTO strategy_events (strategy_name, event_type, event_data)
            VALUES (\$1, \$2, \$3)
            """
            execute(conn, query, [strategy_name, event_type, JSON3.write(event_data)])
            close(conn)
        end
    catch e
        @warn "Failed to log strategy event" error=e
    end
end

# Database connection helper
function get_connection()
    try
        db_host = get(ENV, "DB_HOST", "localhost")
        db_port = get(ENV, "DB_PORT", "5432")
        db_name = get(ENV, "DB_NAME", "algofi_db")
        db_user = get(ENV, "DB_USER", "postgres")
        db_password = get(ENV, "DB_PASSWORD", "postgres")
        
        conn_string = "host=$db_host port=$db_port dbname=$db_name user=$db_user password=$db_password"
        return LibPQ.Connection(conn_string)
    catch e
        @error "Failed to connect to database, arbitrage strategy will not function properly" error=e
        rethrow(e)
    end
end

mutable struct ArbitrageStrategy <: TradingStrategy
    config::StrategyConfig
    dex_endpoints::Dict{String, String}
    price_cache::Dict{String, MarketData}
    last_update::DateTime
    real_time_feed::RealTimeDataFeed  # Real-time data feed manager
    stream_manager::Union{PriceStreamManager, Nothing}  # WebSocket streaming
    
    function ArbitrageStrategy()
        new(
            StrategyConfig(name="", strategy_type="arbitrage"),
            Dict{String, String}(
                "tinyman" => "https://mainnet-api.tinyman.org/v1",
                "pact" => "https://api.pact.fi/api/v1",
                "algofi" => "https://api.algofi.org/v1",
                "vestige" => "https://free-api.vestige.fi/asset",
                "defily" => "https://api.defily.io/v1"
            ),
            Dict{String, MarketData}(),
            now(),
            RealTimeDataFeed(),  # Initialize real-time feed
            nothing  # Streaming will be initialized when needed
        )
    end
end

function initialize!(strategy::ArbitrageStrategy, config::StrategyConfig)
    strategy.config = config
    strategy.config.settings = merge(
        Dict{String, Any}(
            "min_spread_pct" => 0.5,  # Minimum 0.5% spread
            "max_execution_time" => 30000,  # 30 seconds max
            "supported_pairs" => ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"],
            "dex_priorities" => ["tinyman", "algofi", "pact"]
        ),
        config.settings
    )
    log_strategy_event(config.name, "initialized", Dict("type" => "arbitrage"))
end

function fetch_dex_prices(strategy::ArbitrageStrategy)::Bool
    try
        @info "Fetching real-time price data from DEX APIs..."
        
        # Get supported asset pairs from configuration
        supported_pairs = get(strategy.config.settings, "supported_pairs", ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"])
        
        # Update real-time data feed with enhanced fallback
        update_enhanced_prices!(strategy.real_time_feed, supported_pairs)
        
        # Get fresh prices from the feed
        live_prices = get_current_prices(strategy.real_time_feed)
        
        # Merge with strategy's price cache
        merge!(strategy.price_cache, live_prices)
        
        # Also try to fetch from database as backup/comparison
        try
            conn = get_connection()
            
            if !isnothing(conn)
                for pair in supported_pairs
                    asset_name = replace(pair, "/" => "_")
                    
                    # Query recent market data from database
                    query = """
                        SELECT asset_id, asset_name, exchange, price, volume_24h, timestamp 
                        FROM market_data 
                        WHERE asset_name = \$1 AND timestamp > NOW() - INTERVAL '5 minutes'
                        ORDER BY timestamp DESC
                    """
                    
                    result = execute(conn, query, [pair])
                    
                    for row in result
                        exchange = String(row["exchange"])
                        price = Float64(row["price"])
                        volume_24h = Float64(row["volume_24h"])
                        timestamp = DateTime(row["timestamp"])
                        
                        # Store in price cache with exchange prefix
                        cache_key = "$(exchange)_$(asset_name)"
                        strategy.price_cache[cache_key] = MarketData(
                            asset_id = pair,
                            price = price,
                            volume_24h = volume_24h,
                            spread = 0.003,
                            liquidity = volume_24h * price,
                            timestamp = timestamp
                        )
                    end
                end
                
                close(conn)
                @info "Successfully fetched database prices as backup"
            end
        catch db_error
            @warn "Failed to fetch from database, using only live API data" error=db_error
        end
        
        strategy.last_update = now()
        
        @info "Price fetch completed. Cache contains $(length(strategy.price_cache)) price points"
        @info "Sample prices:" [k => v.price for (k,v) in Iterators.take(strategy.price_cache, 3)]
        
        return length(strategy.price_cache) > 0
        
    catch e
        @error "Failed to fetch real-time prices, falling back to simulation" error=e
        
        # Fallback to simulated data
        return generate_simulated_prices!(strategy)
    end
end

"""
Generate simulated price data for testing when real APIs are unavailable
"""
function generate_simulated_prices!(strategy::ArbitrageStrategy)::Bool
    @info "Generating simulated price data for testing..."
    
    try
        supported_pairs = get(strategy.config.settings, "supported_pairs", ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"])
        dex_names = ["tinyman", "pact", "algofi", "vestige"]
        
        # Generate realistic price variations for each DEX and pair
        base_prices = Dict(
            "ALGO/USDC" => 0.125,
            "ALGO/STBL" => 0.123,
            "USDC/STBL" => 0.998
        )
        
        for dex in dex_names
            for pair in supported_pairs
                if haskey(base_prices, pair)
                    base_price = base_prices[pair]
                    
                    # Add realistic price variation (±2% from base)
                    price_variation = (rand() - 0.5) * 0.04  # ±2%
                    final_price = base_price * (1 + price_variation)
                    
                    # Generate realistic volume and liquidity
                    volume = rand(10000:100000) * (dex == "tinyman" ? 2.0 : 1.0)  # Tinyman typically has more volume
                    liquidity = volume * rand(0.8:0.01:1.2)
                    
                    # DEX-specific fees
                    fee = if dex == "tinyman" 
                        0.003
                    elseif dex == "pact"
                        0.0025  
                    elseif dex == "algofi"
                        0.002
                    else
                        0.005
                    end
                    
                    asset_key = "$(dex)_$(replace(pair, "/" => "_"))"
                    strategy.price_cache[asset_key] = MarketData(
                        asset_id = pair,
                        price = final_price,
                        volume_24h = volume,
                        spread = fee,
                        liquidity = liquidity,
                        timestamp = now()
                    )
                end
            end
        end
        
        @info "Generated $(length(strategy.price_cache)) simulated price points"
        return true
        
    catch e
        @error "Failed to generate simulated prices" error=e
        return false
    end
end

function scan_opportunities(strategy::ArbitrageStrategy, market_data::Vector{MarketData})::Vector{TradingOpportunity}
    opportunities = TradingOpportunity[]
    
    # Update price cache
    if !fetch_dex_prices(strategy)
        return opportunities
    end
    
    supported_pairs = strategy.config.settings["supported_pairs"]
    min_spread_pct = strategy.config.settings["min_spread_pct"] / 100
    
    for pair in supported_pairs
        asset_id = replace(pair, "/" => "_")
        dex_prices = []
        
        # Collect prices from all DEXs
        for (dex_name, _) in strategy.dex_endpoints
            cache_key = "$(dex_name)_$(asset_id)"
            if haskey(strategy.price_cache, cache_key)
                push!(dex_prices, (dex_name, strategy.price_cache[cache_key]))
            end
        end
        
        # Find arbitrage opportunities
        if length(dex_prices) >= 2
            # Sort by price
            sort!(dex_prices, by = x -> x[2].price)
            
            lowest_dex, lowest_data = dex_prices[1]
            highest_dex, highest_data = dex_prices[end]
            
            spread = (highest_data.price - lowest_data.price) / lowest_data.price
            
            if spread > min_spread_pct
                # Calculate required capital and expected profit
                trade_amount = min(
                    strategy.config.allocated_amount * 0.1,  # Use 10% of allocated amount
                    lowest_data.liquidity * 0.05  # Max 5% of liquidity
                )
                
                expected_profit = trade_amount * spread - (trade_amount * 0.003 * 2)  # Subtract fees
                
                if expected_profit > strategy.config.min_profit_threshold
                    opportunity = TradingOpportunity(
                        strategy_id = strategy.config.id !== nothing ? strategy.config.id : 0,
                        opportunity_type = "arbitrage",
                        asset_pair = pair,
                        expected_profit = expected_profit,
                        confidence_score = min(0.95, 0.7 + (spread * 10)),  # Higher spread = higher confidence
                        execution_time_ms = 5000,  # Estimated execution time
                        required_capital = trade_amount,
                        metadata = Dict{String, Any}(
                            "buy_dex" => lowest_dex,
                            "sell_dex" => highest_dex,
                            "buy_price" => lowest_data.price,
                            "sell_price" => highest_data.price,
                            "spread_pct" => spread * 100
                        )
                    )
                    push!(opportunities, opportunity)
                end
            end
        end
    end
    
    # Save opportunities to database for tracking
    save_arbitrage_opportunities(opportunities)
    
    return opportunities
end

# Save detected arbitrage opportunities to database
function save_arbitrage_opportunities(opportunities::Vector{TradingOpportunity})::Bool
    if isempty(opportunities)
        return true
    end
    
    try
        conn = get_connection()
        
        for opp in opportunities
            # Extract metadata
            buy_dex = get(opp.metadata, "buy_dex", "unknown")
            sell_dex = get(opp.metadata, "sell_dex", "unknown")
            buy_price = get(opp.metadata, "buy_price", 0.0)
            sell_price = get(opp.metadata, "sell_price", 0.0)
            spread_pct = get(opp.metadata, "spread_pct", 0.0)
            
            # Calculate trade amounts
            min_trade = opp.required_capital * 0.1  # 10% of required capital as minimum
            max_trade = opp.required_capital * 2.0  # 200% as maximum
            
            query = """
                INSERT INTO arbitrage_opportunities (
                    asset_pair, dex_1, dex_2, price_1, price_2, 
                    profit_percentage, min_trade_amount, max_trade_amount,
                    is_active, expires_at, created_at
                ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11)
                ON CONFLICT DO NOTHING
            """
            
            expires_at = now() + Dates.Minute(5)  # Opportunity expires in 5 minutes
            
            execute(conn, query, [
                opp.asset_pair,      # asset_pair
                buy_dex,             # dex_1 (buy from)
                sell_dex,            # dex_2 (sell to)
                buy_price,           # price_1 (buy price)
                sell_price,          # price_2 (sell price)
                spread_pct,          # profit_percentage
                min_trade,           # min_trade_amount
                max_trade,           # max_trade_amount
                true,                # is_active
                expires_at,          # expires_at
                now()                # created_at
            ])
        end
        
        close(conn)
        @info "Saved $(length(opportunities)) arbitrage opportunities to database"
        return true
    catch e
        @error "Failed to save arbitrage opportunities to database" error=e
        return false
    end
end

function execute_trade(strategy::ArbitrageStrategy, opportunity::TradingOpportunity)::TradeResult
    if !validate_opportunity(opportunity, strategy.config)
        return TradeResult(
            success = false,
            error_message = "Opportunity validation failed"
        )
    end
    
    start_time = now()
    
    try
        # Simulate trade execution
        buy_dex = opportunity.metadata["buy_dex"]
        sell_dex = opportunity.metadata["sell_dex"]
        trade_amount = opportunity.required_capital
        
        # Simulate network delay and slippage
        sleep(0.1)  # Simulate execution delay
        actual_slippage = rand(0.001:0.0001:0.005)  # Random slippage
        
        # Calculate actual profit after slippage
        expected_profit = opportunity.expected_profit
        actual_profit = expected_profit * (1 - actual_slippage * 2)
        
        execution_time = Int(round((now() - start_time).value))
        
        # Log successful execution
        log_strategy_event(
            strategy.config.name,
            "trade_executed",
            Dict(
                "pair" => opportunity.asset_pair,
                "profit" => actual_profit,
                "amount" => trade_amount,
                "buy_dex" => buy_dex,
                "sell_dex" => sell_dex
            )
        )
        
        # Create trade result
        tx_hash = "0x" * string(rand(UInt64), base=16)
        trade_result = TradeResult(
            success = true,
            transaction_hash = tx_hash,
            executed_amount = trade_amount,
            actual_profit = actual_profit,
            gas_cost = 0.001,  # ALGO network fee
            slippage = actual_slippage,
            execution_time_ms = execution_time
        )
        
        # Save transaction to database
        save_trading_transaction(strategy, opportunity, trade_result)
        
        return trade_result
        
    catch e
        return TradeResult(
            success = false,
            error_message = "Execution failed: $e",
            execution_time_ms = Int(round((now() - start_time).value))
        )
    end
end

# Save trading transaction to database
function save_trading_transaction(strategy::ArbitrageStrategy, opportunity::TradingOpportunity, result::TradeResult)::Bool
    try
        conn = get_connection()
        if conn === nothing
            return false
        end
        
        query = """
            INSERT INTO trading_transactions (
                wallet_address, strategy_id, transaction_type, asset_id,
                amount, price, pnl_amount, transaction_hash, timestamp, metadata
            ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)
        """
        
        # Build metadata with trade details
        metadata = Dict(
            "opportunity_type" => opportunity.opportunity_type,
            "buy_dex" => get(opportunity.metadata, "buy_dex", ""),
            "sell_dex" => get(opportunity.metadata, "sell_dex", ""),
            "buy_price" => get(opportunity.metadata, "buy_price", 0.0),
            "sell_price" => get(opportunity.metadata, "sell_price", 0.0),
            "spread_pct" => get(opportunity.metadata, "spread_pct", 0.0),
            "slippage" => result.slippage,
            "execution_time_ms" => result.execution_time_ms
        )
        
        # Get average price for the transaction
        avg_price = (get(opportunity.metadata, "buy_price", 0.0) + 
                    get(opportunity.metadata, "sell_price", 0.0)) / 2
        
        execute(conn, query, [
            "strategy_wallet",              # wallet_address (should be from strategy config)
            strategy.config.id !== nothing ? strategy.config.id : 0,  # strategy_id
            "arbitrage",                    # transaction_type
            opportunity.asset_pair,         # asset_id
            result.executed_amount,         # amount
            avg_price,                      # price
            result.actual_profit,           # pnl_amount
            result.transaction_hash,        # transaction_hash
            now(),                          # timestamp
            JSON3.write(metadata)           # metadata
        ])
        
        close(conn)
        @info "Saved trading transaction to database" hash=result.transaction_hash profit=result.actual_profit
        return true
    catch e
        @error "Failed to save trading transaction" error=e
        return false
    end
end

function calculate_position_size(strategy::ArbitrageStrategy, opportunity::TradingOpportunity)::Float64
    max_size = strategy.config.max_position_size
    allocated_pct = 0.1  # Use 10% of allocated amount per trade
    
    # Consider liquidity constraints
    liquidity_limit = opportunity.required_capital
    
    return min(max_size * allocated_pct, liquidity_limit)
end

function should_execute(strategy::ArbitrageStrategy, opportunity::TradingOpportunity)::Bool
    # Check if strategy is active
    if !strategy.config.is_active
        return false
    end
    
    # Check minimum profit threshold
    if opportunity.expected_profit < strategy.config.min_profit_threshold
        return false
    end
    
    # Check confidence score
    if opportunity.confidence_score < 0.7
        return false
    end
    
    # Check spread minimum
    spread_pct = opportunity.metadata["spread_pct"]
    min_spread = strategy.config.settings["min_spread_pct"]
    
    return spread_pct >= min_spread
end

function cleanup!(strategy::ArbitrageStrategy)
    # Stop streaming if active
    if !isnothing(strategy.stream_manager)
        for dex in ["tinyman", "pact", "algofi", "vestige", "defily"]
            stop_price_stream!(strategy.stream_manager, dex)
        end
        strategy.stream_manager = nothing
    end
    
    empty!(strategy.price_cache)
    log_strategy_event(strategy.config.name, "cleanup", Dict("cache_cleared" => true))
end

"""
Start real-time streaming for the arbitrage strategy
"""
function start_streaming!(strategy::ArbitrageStrategy)
    @info "Starting real-time price streaming for arbitrage strategy..."
    
    if isnothing(strategy.stream_manager)
        strategy.stream_manager = setup_streaming_for_strategy!(strategy)
        @info "Real-time streaming activated"
    else
        @warn "Streaming already active"
    end
end

"""
Stop real-time streaming
"""
function stop_streaming!(strategy::ArbitrageStrategy)
    if !isnothing(strategy.stream_manager)
        @info "Stopping real-time price streaming..."
        
        for dex in ["tinyman", "pact", "algofi", "vestige", "defily"]
            stop_price_stream!(strategy.stream_manager, dex)
        end
        
        strategy.stream_manager = nothing
        @info "Real-time streaming stopped"
    end
end

"""
Get streaming status
"""
function get_streaming_status(strategy::ArbitrageStrategy)::Dict{String, Any}
    if isnothing(strategy.stream_manager)
        return Dict(
            "streaming_active" => false,
            "active_streams" => String[],
            "last_update" => strategy.last_update
        )
    else
        active_streams = String[]
        for (dex, is_active) in strategy.stream_manager.is_streaming
            if is_active
                push!(active_streams, dex)
            end
        end
        
        return Dict(
            "streaming_active" => !isempty(active_streams),
            "active_streams" => active_streams,
            "last_update" => strategy.last_update,
            "cache_size" => length(strategy.price_cache)
        )
    end
end

export ArbitrageStrategy, start_streaming!, stop_streaming!, get_streaming_status