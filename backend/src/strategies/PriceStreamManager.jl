"""
WebSocket Streaming for Real-Time Price Updates
Provides live streaming price data for immediate arbitrage detection
"""

using HTTP.WebSockets, JSON3, Dates

"""
WebSocket streaming manager for real-time price updates
"""
mutable struct PriceStreamManager
    streams::Dict{String, WebSocket}
    callbacks::Dict{String, Function}
    is_streaming::Dict{String, Bool}
    update_interval::Int
    
    function PriceStreamManager()
        new(
            Dict{String, WebSocket}(),
            Dict{String, Function}(),
            Dict{String, Bool}(),
            1000  # 1 second update interval
        )
    end
end

"""
Start streaming prices from a DEX WebSocket
"""
function start_price_stream!(manager::PriceStreamManager, dex_name::String, callback::Function)
    if haskey(manager.is_streaming, dex_name) && manager.is_streaming[dex_name]
        @warn "Stream already active for $dex_name"
        return
    end
    
    manager.callbacks[dex_name] = callback
    manager.is_streaming[dex_name] = false
    
    # Start WebSocket connection in a separate task
    @async begin
        try
            ws_url = get_websocket_url(dex_name)
            
            if !isnothing(ws_url)
                @info "Starting WebSocket stream for $dex_name at $ws_url"
                
                WebSockets.open(ws_url) do ws
                    manager.streams[dex_name] = ws
                    manager.is_streaming[dex_name] = true
                    
                    # Subscribe to price updates
                    subscribe_message = create_subscribe_message(dex_name)
                    send(ws, subscribe_message)
                    
                    # Listen for messages
                    for msg in ws
                        try
                            if manager.is_streaming[dex_name]
                                data = JSON3.read(String(msg))
                                process_stream_message(manager, dex_name, data)
                            else
                                break
                            end
                        catch e
                            @error "Error processing WebSocket message from $dex_name" error=e
                        end
                    end
                end
            else
                @warn "No WebSocket URL available for $dex_name, falling back to polling"
                start_polling_stream(manager, dex_name)
            end
            
        catch e
            @error "WebSocket connection failed for $dex_name" error=e
            manager.is_streaming[dex_name] = false
            
            # Fallback to HTTP polling
            start_polling_stream(manager, dex_name)
        end
    end
    
    @info "Price stream initiated for $dex_name"
end

"""
Stop streaming prices from a DEX
"""
function stop_price_stream!(manager::PriceStreamManager, dex_name::String)
    if haskey(manager.is_streaming, dex_name)
        manager.is_streaming[dex_name] = false
        
        if haskey(manager.streams, dex_name)
            try
                close(manager.streams[dex_name])
                delete!(manager.streams, dex_name)
            catch e
                @warn "Error closing WebSocket for $dex_name" error=e
            end
        end
        
        @info "Stopped price stream for $dex_name"
    end
end

"""
Get WebSocket URL for different DEX providers
"""
function get_websocket_url(dex_name::String)::Union{String, Nothing}
    urls = Dict(
        "tinyman" => nothing,  # Tinyman doesn't have public WebSocket API
        "pact" => "wss://api.pact.fi/ws",  # Hypothetical
        "algofi" => nothing,   # AlgoFi doesn't have public WebSocket API  
        "vestige" => "wss://api.vestige.fi/ws",  # Hypothetical
        "defily" => nothing
    )
    
    return get(urls, dex_name, nothing)
end

"""
Create subscribe message for different DEX WebSocket formats
"""
function create_subscribe_message(dex_name::String)::String
    if dex_name == "pact"
        return JSON3.write(Dict(
            "event" => "subscribe",
            "channel" => "prices",
            "symbols" => ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"]
        ))
    elseif dex_name == "vestige"
        return JSON3.write(Dict(
            "type" => "subscribe",
            "streams" => ["ticker@ALL"]
        ))
    else
        return JSON3.write(Dict("action" => "subscribe", "channel" => "prices"))
    end
end

"""
Process incoming WebSocket message and trigger callback
"""
function process_stream_message(manager::PriceStreamManager, dex_name::String, data::Dict)
    try
        if haskey(manager.callbacks, dex_name)
            # Parse price data based on DEX format
            price_updates = parse_price_data(dex_name, data)
            
            if !isempty(price_updates)
                # Trigger callback with new price data
                manager.callbacks[dex_name](price_updates)
            end
        end
    catch e
        @error "Error processing stream message for $dex_name" error=e
    end
end

"""
Parse price data from WebSocket message based on DEX format
"""
function parse_price_data(dex_name::String, data::Dict)::Vector{MarketData}
    price_updates = MarketData[]
    
    try
        if dex_name == "pact" && haskey(data, "data") && haskey(data["data"], "price")
            # Pact format example
            symbol = get(data["data"], "symbol", "UNKNOWN")
            price = Float64(data["data"]["price"])
            volume = Float64(get(data["data"], "volume", 0.0))
            
            push!(price_updates, MarketData(
                symbol,
                price,
                volume,
                0.0025,  # Pact fee
                volume * price,
                now()
            ))
            
        elseif dex_name == "vestige" && haskey(data, "stream") && data["stream"] == "ticker"
            # Vestige format example
            if haskey(data, "data")
                symbol = get(data["data"], "s", "UNKNOWN")
                price = parse(Float64, get(data["data"], "c", "0"))
                volume = parse(Float64, get(data["data"], "v", "0"))
                
                push!(price_updates, MarketData(
                    symbol,
                    price,
                    volume,
                    0.005,  # Default fee
                    volume * price,
                    now()
                ))
            end
        end
        
    catch e
        @error "Error parsing price data for $dex_name" error=e data
    end
    
    return price_updates
end

"""
Fallback HTTP polling for DEXs without WebSocket API
"""
function start_polling_stream(manager::PriceStreamManager, dex_name::String)
    @info "Starting HTTP polling stream for $dex_name"
    
    @async begin
        while get(manager.is_streaming, dex_name, false)
            try
                # Create a temporary RealTimeDataFeed for polling
                feed = RealTimeDataFeed()
                
                if dex_name == "tinyman"
                    prices = fetch_tinyman_prices(feed, ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"])
                elseif dex_name == "algofi"
                    prices = fetch_algofi_prices(feed, ["ALGO/USDC", "ALGO/STBL", "USDC/STBL"])
                else
                    prices = Dict{String, MarketData}()
                end
                
                if !isempty(prices) && haskey(manager.callbacks, dex_name)
                    # Convert to MarketData vector and trigger callback
                    price_updates = collect(values(prices))
                    manager.callbacks[dex_name](price_updates)
                end
                
            catch e
                @error "Error in HTTP polling for $dex_name" error=e
            end
            
            sleep(manager.update_interval / 1000)  # Convert ms to seconds
        end
    end
end

"""
Setup streaming for arbitrage strategy
"""
function setup_streaming_for_strategy!(strategy)
    stream_manager = PriceStreamManager()
    
    # Define callback function for price updates
    price_update_callback = function(price_updates::Vector{MarketData})
        @info "Received $(length(price_updates)) price updates"
        
        # Update strategy's price cache
        for price_data in price_updates
            cache_key = "stream_$(replace(price_data.asset_pair, "/" => "_"))"
            strategy.price_cache[cache_key] = price_data
        end
        
        # Trigger opportunity scan with new data
        opportunities = scan_opportunities(strategy, price_updates)
        if !isempty(opportunities)
            @info "🚨 Found $(length(opportunities)) streaming arbitrage opportunities!"
            
            # Save opportunities to database
            save_arbitrage_opportunities(opportunities)
        end
    end
    
    # Start streams for supported DEXs
    dex_list = ["pact", "vestige", "tinyman", "algofi"]  # Priority order
    for dex in dex_list
        start_price_stream!(stream_manager, dex, price_update_callback)
    end
    
    return stream_manager
end

export PriceStreamManager, start_price_stream!, stop_price_stream!, setup_streaming_for_strategy!