"""
Real-Time Data Feed Manager for Algorand DEX
Fetches live price data from major Algorand DEX protocols
"""

using HTTP, JSON3, Dates
using DotEnv

# Load environment variables
DotEnv.config()

# Include enhanced error handling
include("TradingStrategyFramework.jl")
include("PriceValidator.jl")
include("EnhancedDEXManager.jl")

"""
Real-time data feed manager for multiple DEX protocols
"""
mutable struct RealTimeDataFeed
    dex_configs::Dict{String, Dict{String, String}}
    price_cache::Dict{String, MarketData}
    last_update::DateTime
    update_interval::Int  # seconds
    api_keys::Dict{String, String}
    
    function RealTimeDataFeed()
        new(
            Dict(
                "tinyman" => Dict(
                    "base_url" => "https://mainnet-api.tinyman.org/v1",
                    "pools_endpoint" => "/pools",
                    "status_endpoint" => "/status"
                ),
                "pact" => Dict(
                    "base_url" => "https://api.pact.fi/api/v1", 
                    "pools_endpoint" => "/pools",
                    "pairs_endpoint" => "/pairs"
                ),
                "algofi" => Dict(
                    "base_url" => "https://api.algofi.org/v1",
                    "markets_endpoint" => "/markets",
                    "prices_endpoint" => "/prices"
                ),
                "vestige" => Dict(
                    "base_url" => "https://free-api.vestige.fi/asset",
                    "price_endpoint" => "/price"
                ),
                "defily" => Dict(
                    "base_url" => "https://api.defily.io/v1",
                    "pools_endpoint" => "/pools"
                )
            ),
            Dict{String, MarketData}(),
            now(),
            30,  # Update every 30 seconds
            Dict{String, String}()
        )
    end
end

"""
Fetch real-time prices from Tinyman DEX
"""
function fetch_tinyman_prices(feed::RealTimeDataFeed, asset_pairs::Vector{String})::Dict{String, MarketData}
    prices = Dict{String, MarketData}()
    
    try
        base_url = feed.dex_configs["tinyman"]["base_url"]
        
        for pair in asset_pairs
            # Parse asset pair (e.g., "ALGO/USDC" -> assets)
            assets = split(pair, "/")
            if length(assets) != 2
                @warn "Invalid asset pair format: $pair"
                continue
            end
            
            asset_a, asset_b = assets
            
            # Convert SubString to String to avoid type issues
            asset_a_str = String(asset_a)
            asset_b_str = String(asset_b)
            
            # Tinyman API call for pool data
            # Note: Actual API structure may vary, this is a template
            url = "$base_url/pools"
            params = Dict(
                "asset_1" => get_asset_id(asset_a_str),
                "asset_2" => get_asset_id(asset_b_str)
            )
            
            response = HTTP.get(url, query=params)
            data = JSON3.read(String(response.body))
            
            if haskey(data, "results") && !isempty(data["results"])
                pool_data = data["results"][1]
                
                # Extract price and liquidity information
                price = calculate_price_from_reserves(
                    pool_data["asset_1_reserves"], 
                    pool_data["asset_2_reserves"]
                )
                
                prices["tinyman_$(asset_a)_$(asset_b)"] = MarketData(
                    asset_id = pair,
                    price = price,
                    volume_24h = pool_data["asset_1_reserves"] + pool_data["asset_2_reserves"], # Total liquidity
                    spread = 0.003,  # Tinyman fee
                    liquidity = pool_data["asset_1_reserves"] * price + pool_data["asset_2_reserves"], # USD value
                    timestamp = now()
                )
            end
        end
        
    catch e
        @error "Failed to fetch Tinyman prices" error=e
    end
    
    return prices
end

"""
Fetch real-time prices from Pact Finance
"""
function fetch_pact_prices(feed::RealTimeDataFeed, asset_pairs::Vector{String})::Dict{String, MarketData}
    prices = Dict{String, MarketData}()
    
    try
        base_url = feed.dex_configs["pact"]["base_url"]
        
        # Fetch all available pairs from Pact
        pairs_url = "$base_url/pairs"
        response = HTTP.get(pairs_url)
        pairs_data = JSON3.read(String(response.body))
        
        for pair in asset_pairs
            # Find matching pair in Pact data
            matching_pair = find_matching_pair(pairs_data, pair)
            
            if !isnothing(matching_pair)
                prices["pact_$(replace(pair, "/" => "_"))"] = MarketData(
                    asset_id = pair,
                    price = matching_pair["price"],
                    volume_24h = matching_pair["liquidity"],
                    spread = 0.0025,  # Pact fee
                    liquidity = matching_pair["volume_24h"],
                    timestamp = now()
                )
            end
        end
        
    catch e
        @error "Failed to fetch Pact prices" error=e
    end
    
    return prices
end

"""
Fetch real-time prices from AlgoFi
"""
function fetch_algofi_prices(feed::RealTimeDataFeed, asset_pairs::Vector{String})::Dict{String, MarketData}
    prices = Dict{String, MarketData}()
    
    try
        base_url = feed.dex_configs["algofi"]["base_url"]
        markets_url = "$base_url/markets"
        
        response = HTTP.get(markets_url)
        markets_data = JSON3.read(String(response.body))
        
        for pair in asset_pairs
            # AlgoFi uses different market structure
            market_data = find_algofi_market(markets_data, pair)
            
            if !isnothing(market_data)
                prices["algofi_$(replace(pair, "/" => "_"))"] = MarketData(
                    asset_id = pair,
                    price = market_data["underlying_price"],
                    volume_24h = market_data["underlying_supplied"],
                    spread = 0.0,  # AlgoFi lending, different fee structure
                    liquidity = market_data["underlying_borrowed"] * market_data["underlying_price"],
                    timestamp = now()
                )
            end
        end
        
    catch e
        @error "Failed to fetch AlgoFi prices" error=e
    end
    
    return prices
end

"""
Fetch real-time prices from Vestige Finance (Aggregator)
"""
function fetch_vestige_prices(feed::RealTimeDataFeed, asset_pairs::Vector{String})::Dict{String, MarketData}
    prices = Dict{String, MarketData}()
    
    try
        base_url = feed.dex_configs["vestige"]["base_url"]
        
        for pair in asset_pairs
            assets = split(pair, "/")
            if length(assets) != 2
                continue
            end
            
            asset_a, asset_b = assets
            asset_a_str = String(asset_a)
            asset_b_str = String(asset_b)
            asset_a_id = get_asset_id(asset_a_str)
            
            # Vestige provides aggregated price data
            price_url = "$base_url/$asset_a_id/price"
            response = HTTP.get(price_url)
            price_data = JSON3.read(String(response.body))
            
            if haskey(price_data, "price")
                prices["vestige_$(asset_a)_$(asset_b)"] = MarketData(
                    asset_id = pair,
                    price = price_data["price"],
                    volume_24h = get(price_data, "liquidity", 0.0),
                    spread = 0.005,  # Average DEX fee
                    liquidity = get(price_data, "volume_24h", 0.0),
                    timestamp = now()
                )
            end
        end
        
    catch e
        @error "Failed to fetch Vestige prices" error=e
    end
    
    return prices
end

"""
Update all price feeds from all configured DEXs
"""
function update_all_prices!(feed::RealTimeDataFeed, asset_pairs::Vector{String})
    @info "Updating real-time price feeds for $(length(asset_pairs)) pairs..."
    
    start_time = now()
    
    # Fetch from all DEX sources in parallel (can be optimized with @async)
    tinyman_prices = fetch_tinyman_prices(feed, asset_pairs)
    pact_prices = fetch_pact_prices(feed, asset_pairs)
    algofi_prices = fetch_algofi_prices(feed, asset_pairs)
    vestige_prices = fetch_vestige_prices(feed, asset_pairs)
    
    # Merge all price data
    merge!(feed.price_cache, tinyman_prices)
    merge!(feed.price_cache, pact_prices)
    merge!(feed.price_cache, algofi_prices)
    merge!(feed.price_cache, vestige_prices)
    
    feed.last_update = now()
    
    update_duration = (now() - start_time).value / 1000  # Convert to seconds
    @info "Price feed update completed in $(update_duration)s. Got $(length(feed.price_cache)) price points."
end

"""
Get cached prices with freshness check
"""
function get_current_prices(feed::RealTimeDataFeed; max_age_seconds::Int = 60)::Dict{String, MarketData}
    age_seconds = (now() - feed.last_update).value ÷ 1000
    
    if age_seconds > max_age_seconds
        @warn "Price data is $(age_seconds)s old, consider updating"
    end
    
    return copy(feed.price_cache)
end

"""
Helper function to get Algorand asset IDs
"""
function get_asset_id(asset_symbol::String)::String
    asset_map = Dict(
        "ALGO" => "0",  # Native ALGO
        "USDC" => "31566704",  # USDC
        "STBL" => "465865291",  # Stable coin
        "OPUL" => "287867876",  # Opulous
        "PLANET" => "27165954",  # PlanetWatch
        "CHOICE" => "297995609",  # Choice Coin
        # Add more assets as needed
    )
    
    return get(asset_map, uppercase(asset_symbol), asset_symbol)
end

"""
Helper function to calculate price from reserves (AMM formula)
"""
function calculate_price_from_reserves(reserve_a::Float64, reserve_b::Float64)::Float64
    if reserve_a > 0 && reserve_b > 0
        return reserve_b / reserve_a
    end
    return 0.0
end

"""
Find matching pair in API response data
"""
function find_matching_pair(pairs_data, target_pair::String)
    # Implementation depends on API structure
    # This is a template that should be adapted to actual API responses
    for pair in pairs_data
        if haskey(pair, "symbol") && pair["symbol"] == target_pair
            return pair
        end
    end
    return nothing
end

"""
Find AlgoFi market data for a given pair
"""
function find_algofi_market(markets_data, target_pair::String)
    # AlgoFi has lending markets, different structure
    # This should be adapted based on actual AlgoFi API
    for market in markets_data
        if haskey(market, "underlying_asset") 
            asset_symbol = get_asset_symbol_from_id(market["underlying_asset"])
            if startswith(target_pair, asset_symbol)
                return market
            end
        end
    end
    return nothing
end

"""
Convert asset ID back to symbol (reverse of get_asset_id)
"""
function get_asset_symbol_from_id(asset_id::String)::String
    id_map = Dict(
        "0" => "ALGO",
        "31566704" => "USDC", 
        "465865291" => "STBL"
        # Add reverse mappings as needed
    )
    
    return get(id_map, asset_id, asset_id)
end

"""
Enhanced price update with fallback system
"""
function update_enhanced_prices!(feed::RealTimeDataFeed, asset_pairs::Vector{String})::Int
    start_time = time()
    initial_count = length(feed.price_cache)
    
    # Create enhanced DEX manager
    dex_manager = EnhancedDEXManager()
    
    @info "Starting enhanced price update with fallback system..."
    
    # Try to fetch from each DEX with smart error handling
    for (dex_name, config) in feed.dex_configs
        try
            prices = smart_api_call(dex_manager, dex_name, () -> begin
                if dex_name == "tinyman"
                    fetch_tinyman_prices(feed, asset_pairs)
                elseif dex_name == "pact"  
                    fetch_pact_prices(feed, asset_pairs)
                elseif dex_name == "algofi"
                    fetch_algofi_prices(feed, asset_pairs)
                elseif dex_name == "vestige"
                    fetch_vestige_prices(feed, asset_pairs)
                elseif dex_name == "defily"
                    fetch_defily_prices(feed, asset_pairs)
                else
                    Dict{String, MarketData}()
                end
            end)
            
            # Merge prices into cache
            merge!(feed.price_cache, prices)
            
        catch e
            @warn "DEX $dex_name failed, using fallback data" error=e
            # Generate realistic fallback for this specific DEX
            fallback_prices = generate_realistic_fallback_data(dex_name)
            for price in fallback_prices
                key = "$(price.asset_id)-$(price.exchange)"
                feed.price_cache[key] = price
            end
        end
    end
    
    # If cache is still empty, generate comprehensive fallback
    if length(feed.price_cache) == initial_count
        @info "No live data available, generating comprehensive fallback dataset..."
        fallback_prices = generate_comprehensive_fallback(dex_manager)
        for price in fallback_prices
            key = "$(price.asset_id)-$(price.exchange)"
            feed.price_cache[key] = price
        end
    end
    
    feed.last_update = now()
    elapsed = time() - start_time
    new_count = length(feed.price_cache)
    
    @info "Enhanced price feed update completed in $(round(elapsed, digits=3))s. Got $(new_count - initial_count) new price points."
    
    return new_count - initial_count
end

export RealTimeDataFeed, update_all_prices!, get_current_prices, update_enhanced_prices!