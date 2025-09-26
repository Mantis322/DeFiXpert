"""
Price Data Validation and Quality Control
Ensures data integrity and handles edge cases for trading algorithms
"""

using Dates, Statistics

"""
Price data validator with quality controls
"""
struct PriceValidator
    max_price_change_pct::Float64
    min_volume::Float64
    max_age_seconds::Int
    outlier_threshold::Float64
    
    function PriceValidator()
        new(
            10.0,   # Max 10% price change per minute
            1000.0, # Minimum $1000 volume
            300,    # Max 5 minutes old
            3.0     # 3 standard deviations for outlier detection
        )
    end
end

"""
Validate a single MarketData entry
"""
function validate_price_data(validator::PriceValidator, data::MarketData, 
                            previous_data::Union{MarketData, Nothing} = nothing)::Bool
    
    # Basic sanity checks
    if data.price <= 0 || data.volume_24h < 0 || data.liquidity < 0
        @warn "Invalid price data: negative values" price=data.price volume_24h=data.volume_24h liquidity=data.liquidity
        return false
    end
    
    # Volume validation
    if data.volume_24h < validator.min_volume
        @debug "Low volume data point" asset_id=data.asset_id volume_24h=data.volume_24h min_required=validator.min_volume
        # Don't reject, but flag for low confidence
    end
    
    # Age validation
    age_seconds = (now() - data.timestamp).value ÷ 1000
    if age_seconds > validator.max_age_seconds
        @warn "Stale price data" asset_id=data.asset_id age_seconds=age_seconds
        return false
    end
    
    # Price change validation (if we have previous data)
    if !isnothing(previous_data)
        time_diff_minutes = (data.timestamp - previous_data.timestamp).value ÷ 60000
        if time_diff_minutes > 0
            price_change_pct = abs(data.price - previous_data.price) / previous_data.price * 100
            max_allowed_change = validator.max_price_change_pct * time_diff_minutes
            
            if price_change_pct > max_allowed_change
                @warn "Suspicious price change" asset_id=data.asset_id change_pct=price_change_pct max_allowed=max_allowed_change
                return false
            end
        end
    end
    
    return true
end

"""
Validate and filter a collection of price data
"""
function validate_price_collection(validator::PriceValidator, 
                                  price_data::Dict{String, MarketData})::Dict{String, MarketData}
    
    validated_data = Dict{String, MarketData}()
    
    # Group by asset pair for cross-DEX validation
    pairs_data = Dict{String, Vector{Tuple{String, MarketData}}}()
    
    for (key, data) in price_data
        pair = data.asset_id
        if !haskey(pairs_data, pair)
            pairs_data[pair] = Tuple{String, MarketData}[]
        end
        push!(pairs_data[pair], (key, data))
    end
    
    # Validate each asset pair's data
    for (pair, dex_data) in pairs_data
        if length(dex_data) >= 2
            # Cross-DEX validation
            validated_pair_data = validate_cross_dex_prices(validator, pair, dex_data)
            merge!(validated_data, validated_pair_data)
        else
            # Single DEX data - basic validation
            key, data = dex_data[1]
            if validate_price_data(validator, data)
                validated_data[key] = data
            end
        end
    end
    
    return validated_data
end

"""
Cross-DEX price validation to detect outliers
"""
function validate_cross_dex_prices(validator::PriceValidator, 
                                  pair::String, 
                                  dex_data::Vector{Tuple{String, MarketData}})::Dict{String, MarketData}
    
    validated_data = Dict{String, MarketData}()
    
    if length(dex_data) < 2
        return validated_data
    end
    
    # Extract prices for statistical analysis
    prices = [data.price for (_, data) in dex_data]
    
    # Calculate statistics
    mean_price = mean(prices)
    std_price = std(prices)
    
    # Detect outliers using z-score
    for (key, data) in dex_data
        if std_price > 0
            z_score = abs(data.price - mean_price) / std_price
            
            if z_score <= validator.outlier_threshold
                # Price is within acceptable range
                validated_data[key] = data
            else
                @warn "Outlier price detected" pair=pair dex=split(key, "_")[1] price=data.price mean_price=mean_price z_score=z_score
            end
        else
            # All prices are identical, accept all
            validated_data[key] = data
        end
    end
    
    return validated_data
end

"""
Enhanced price cache with automatic cleanup and validation
"""
mutable struct ValidatedPriceCache
    cache::Dict{String, MarketData}
    validator::PriceValidator
    max_cache_size::Int
    cleanup_threshold::Float64
    
    function ValidatedPriceCache()
        new(
            Dict{String, MarketData}(),
            PriceValidator(),
            10000,  # Max 10k entries
            0.8     # Cleanup when 80% full
        )
    end
end

"""
Add validated price data to cache
"""
function add_price_data!(cache::ValidatedPriceCache, key::String, data::MarketData)
    # Validate against existing data
    previous_data = get(cache.cache, key, nothing)
    
    if validate_price_data(cache.validator, data, previous_data)
        cache.cache[key] = data
        
        # Auto-cleanup if needed
        if length(cache.cache) > cache.max_cache_size * cache.cleanup_threshold
            cleanup_cache!(cache)
        end
        
        return true
    else
        @debug "Price data validation failed, not adding to cache" key=key
        return false
    end
end

"""
Bulk add with cross-validation
"""
function add_price_collection!(cache::ValidatedPriceCache, price_data::Dict{String, MarketData})
    validated_data = validate_price_collection(cache.validator, price_data)
    
    for (key, data) in validated_data
        cache.cache[key] = data
    end
    
    # Auto-cleanup if needed
    if length(cache.cache) > cache.max_cache_size * cache.cleanup_threshold
        cleanup_cache!(cache)
    end
    
    @info "Added $(length(validated_data))/$(length(price_data)) validated price points to cache"
    return length(validated_data)
end

"""
Get fresh price data from cache
"""
function get_fresh_prices(cache::ValidatedPriceCache, max_age_seconds::Int = 300)::Dict{String, MarketData}
    fresh_data = Dict{String, MarketData}()
    cutoff_time = now() - Dates.Second(max_age_seconds)
    
    for (key, data) in cache.cache
        if data.timestamp >= cutoff_time
            fresh_data[key] = data
        end
    end
    
    return fresh_data
end

"""
Cleanup old entries from cache
"""
function cleanup_cache!(cache::ValidatedPriceCache)
    before_size = length(cache.cache)
    
    # Remove entries older than 1 hour
    cutoff_time = now() - Dates.Hour(1)
    
    keys_to_remove = String[]
    for (key, data) in cache.cache
        if data.timestamp < cutoff_time
            push!(keys_to_remove, key)
        end
    end
    
    for key in keys_to_remove
        delete!(cache.cache, key)
    end
    
    # If still too large, remove oldest entries
    if length(cache.cache) > cache.max_cache_size
        sorted_entries = sort(collect(cache.cache), by = x -> x[2].timestamp)
        excess_count = length(cache.cache) - cache.max_cache_size
        
        for i in 1:excess_count
            delete!(cache.cache, sorted_entries[i][1])
        end
    end
    
    after_size = length(cache.cache)
    @info "Cache cleanup: $(before_size) → $(after_size) entries"
end

"""
Get cache statistics
"""
function get_cache_stats(cache::ValidatedPriceCache)::Dict{String, Any}
    if isempty(cache.cache)
        return Dict(
            "size" => 0,
            "oldest_entry" => nothing,
            "newest_entry" => nothing
        )
    end
    
    timestamps = [data.timestamp for data in values(cache.cache)]
    
    return Dict(
        "size" => length(cache.cache),
        "oldest_entry" => minimum(timestamps),
        "newest_entry" => maximum(timestamps),
        "age_range_minutes" => (maximum(timestamps) - minimum(timestamps)).value ÷ 60000
    )
end

export PriceValidator, ValidatedPriceCache, add_price_data!, add_price_collection!, 
       get_fresh_prices, cleanup_cache!, get_cache_stats, validate_price_data