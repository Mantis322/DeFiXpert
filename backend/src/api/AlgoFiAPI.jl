module AlgoFiAPI

using HTTP
using JSON3
using Dates
using TimeZones
using LibPQ  # For PostgreSQL connectivity
using ..AlgoFiUsers
using Base.Threads: @spawn

# --- Lightweight latency/timing helper ---
macro with_timing(label, expr)
    return quote
        local _tstart = time()
        local _res = try
            $(esc(expr))
        catch e
            @error "Failed section $(String($label))" error=e
            rethrow()
        end
        local _dt = (time() - _tstart) * 1000
        @debug "TIMING $(String($label)) ms=$(_dt)"
        _res
    end
end

include("../db/DBConfig.jl")  # Include database configuration
using .DBConfig

include("SwarmAPI.jl")  # Include Swarm API module
include("StakeAPI.jl")  # Include Stake API module

const SERVER = Ref{Any}(nothing)

# --- Simple in-memory cache for price endpoints to avoid blocking DB on every request ---
const PRICE_CACHE = Ref(Dict{String, Any}())  # structure: Dict("prices"=>Dict, "fetched_at"=>DateTime)
const PRICE_CACHE_TTL_SECONDS = 10
const PRICE_CACHE_LOCK = ReentrantLock()

function _refresh_price_cache!()
    lock(PRICE_CACHE_LOCK) do
        try
            @info "Fetching live crypto prices from CoinGecko..."
            # Fetch real-time prices from CoinGecko API
            external_prices = _fetch_external_prices()
            
            # Also try to get any cached DB data as fallback
            db_prices = Dict{String, Any}()
            try
                query = """
                    SELECT asset_pair, dex_name, price, volume_24h, last_updated
                    FROM price_feeds
                    WHERE last_updated > NOW() - INTERVAL '1 hour'
                    ORDER BY asset_pair, dex_name
                """
                rows = execute_query(query)
                for row in rows
                    asset_pair = String(row[1])
                    dex = String(row[2])
                    pr = Float64(row[3])
                    vol = row[4] === nothing ? 0.0 : Float64(row[4])
                    ts = String(row[5])
                    pair_dict = get!(db_prices, asset_pair, Dict{String, Any}())
                    pair_dict[dex] = Dict(
                        "price" => pr,
                        "volume_24h" => vol,
                        "last_updated" => ts
                    )
                end
                @debug "Found $(length(db_prices)) cached DB prices"
            catch db_err
                @warn "DB price fetch failed, using only external" error=db_err
            end
            
            # Merge external and DB prices (external takes priority)
            final_prices = merge(db_prices, external_prices)
            
            PRICE_CACHE[] = Dict(
                "prices" => final_prices,
                "fetched_at" => now()
            )
            @info "Price cache refreshed: $(length(final_prices)) pairs available"
        catch e
            @error "Price cache refresh failed completely" error=e exception=(e, catch_backtrace())
        end
    end
end

function _fetch_external_prices()::Dict{String, Any}
    """Fetch live ALGO/USD prices from multiple exchanges"""
    try
        prices = Dict{String, Any}()
        
        # 1. CoinGecko ALGO price
        @info "Fetching ALGO/USD from CoinGecko..."
        coingecko_url = "https://api.coingecko.com/api/v3/simple/price?ids=algorand&vs_currencies=usd&include_24hr_vol=true&include_24hr_change=true"
        cg_response = HTTP.get(coingecko_url, readtimeout=10)
        
        if cg_response.status == 200
            cg_data = JSON3.read(String(cg_response.body))
            if haskey(cg_data, "algorand") && haskey(cg_data["algorand"], "usd")
                algo_cg = cg_data["algorand"]
                prices["ALGO/USD"] = Dict{String, Any}(
                    "coingecko" => Dict(
                        "price" => Float64(algo_cg.usd),
                        "volume_24h" => get(algo_cg, :usd_24h_vol, 0.0),
                        "change_24h" => get(algo_cg, :usd_24h_change, 0.0),
                        "last_updated" => string(now())
                    )
                )
            end
        end
        
        # 2. HTX ALGO/USDT price (convert to USD)
        @info "Fetching ALGO/USDT from HTX..."
        try
            htx_url = "https://api.huobi.pro/market/detail/merged?symbol=algousdt"
            htx_response = HTTP.get(htx_url, readtimeout=10)
            
            if htx_response.status == 200
                htx_data = JSON3.read(String(htx_response.body))
                if haskey(htx_data, "tick") && haskey(htx_data["tick"], "close")
                    htx_price = Float64(htx_data["tick"]["close"])
                    htx_volume = get(htx_data["tick"], "vol", 0.0)
                    
                    if !haskey(prices, "ALGO/USD")
                        prices["ALGO/USD"] = Dict{String, Any}()
                    end
                    
                    prices["ALGO/USD"]["htx"] = Dict(
                        "price" => htx_price,
                        "volume_24h" => Float64(htx_volume),
                        "change_24h" => 0.0,  # HTX doesn't provide change in this endpoint
                        "last_updated" => string(now())
                    )
                end
            end
        catch htx_err
            @warn "HTX fetch failed" error=htx_err
        end

        # 3. Tinyman simulation (slightly different price for demonstration)
        @info "Simulating Tinyman ALGO/USD price..."
        try
            if haskey(prices, "ALGO/USD") && haskey(prices["ALGO/USD"], "coingecko")
                base_price = prices["ALGO/USD"]["coingecko"]["price"]
                # Simulate Tinyman price with larger variance (-1% to +1%) for testing
                variance = (rand() - 0.5) * 0.02  # -1% to +1% (increased from 0.01)
                tinyman_price = base_price * (1.0 + variance)
                
                prices["ALGO/USD"]["tinyman"] = Dict(
                    "price" => tinyman_price,
                    "volume_24h" => 850000.0 + rand() * 200000.0,  # Simulated volume
                    "change_24h" => get(prices["ALGO/USD"]["coingecko"], "change_24h", 0.0) + (rand() - 0.5) * 0.5,
                    "last_updated" => string(now())
                )
            end
        catch tinyman_err
            @warn "Tinyman simulation failed" error=tinyman_err
        end
        
        @info "Fetched ALGO/USD from $(length(get(prices, "ALGO/USD", Dict()))) exchanges"
        return prices
        
    catch e
        @error "External price fetch failed" error=e exception=(e, catch_backtrace())
        return Dict{String, Any}()
    end
end

function _maybe_refresh_cache_async()
    # spawn async refresh if stale
    try
        local stale = false
        lock(PRICE_CACHE_LOCK) do
            if isempty(PRICE_CACHE[]) || !haskey(PRICE_CACHE[], "fetched_at")
                stale = true
            else
                age = (now() - PRICE_CACHE[]["fetched_at"]).value / 1000
                if age > PRICE_CACHE_TTL_SECONDS
                    stale = true
                end
            end
        end
        if stale
            @spawn _refresh_price_cache!()
        end
    catch e
        @warn "Failed to trigger async price cache refresh" error=e
    end
end

# Helper function to convert JSON3.Object to Dict recursively
function json_to_dict(obj)
    if isa(obj, JSON3.Object)
        return Dict{String, Any}(String(k) => json_to_dict(v) for (k, v) in obj)
    elseif isa(obj, JSON3.Array)
        return [json_to_dict(item) for item in obj]
    else
        return obj
    end
end

# Database connection helper with timeout and retry logic
function get_connection()
    max_retries = 3
    retry_count = 0
    
    while retry_count < max_retries
        try
            # Create connection with timeout settings
            conn_string = DBConfig.get_db_connection_string()
            conn = LibPQ.Connection(conn_string)
            
            # Test connection with quick query
            result = LibPQ.execute(conn, "SELECT 1")
            return conn
            
        catch e
            retry_count += 1
            @warn "Database connection attempt $retry_count failed" error=e
            
            if retry_count < max_retries
                sleep(0.5)  # Wait 500ms before retry
            else
                @error "Failed to establish database connection after $max_retries attempts"
                return nothing
            end
        end
    end
    
    return nothing
end

# Fast database query with automatic cleanup
function execute_query(query::String, params = [])
    conn = get_connection()
    if conn === nothing
        throw(ErrorException("Database connection failed"))
    end
    
    try
        local result = @with_timing (:db_execute) begin
            isempty(params) ? LibPQ.execute(conn, query) : LibPQ.execute(conn, query, params)
        end
        data = @with_timing (:db_collect) [row for row in result]  # Convert to array immediately
        close(conn)
        return data
    catch e
        close(conn)
        rethrow(e)
    end
end

export setup_algofi_routes!, run_server

# Helper function to add CORS headers to any response
function add_cors_headers(response::HTTP.Response, origin::String="*")
    HTTP.setheader(response, "Access-Control-Allow-Origin" => origin)
    HTTP.setheader(response, "Vary" => "Origin")
    HTTP.setheader(response, "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS")
    # Broaden allowed headers to satisfy browser preflight (include common ones)
    HTTP.setheader(response, "Access-Control-Allow-Headers" => "Content-Type, Authorization, Accept, Origin, X-Requested-With")
    HTTP.setheader(response, "Access-Control-Allow-Credentials" => "true")
    HTTP.setheader(response, "Access-Control-Max-Age" => "600")
    return response
end

# CORS middleware function
function cors_middleware(handler)
    return function(req::HTTP.Request)
        origin = HTTP.header(req, "Origin", "*")
        req_headers = HTTP.header(req, "Access-Control-Request-Headers", "")
        allow_headers = isempty(req_headers) ? "Content-Type, Authorization" : req_headers

        # Preflight (CORS)
        if req.method == "OPTIONS"
            return HTTP.Response(204, [
                "Access-Control-Allow-Origin" => origin,
                "Vary" => "Origin",
                "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
                "Access-Control-Allow-Headers" => allow_headers,
                "Access-Control-Allow-Credentials" => "true"
            ])
        end
        
        # Execute the actual handler
        try
            res = handler(req)
            # Add CORS headers to response
            HTTP.setheader(res, "Access-Control-Allow-Origin" => origin)
            HTTP.setheader(res, "Vary" => "Origin")
            HTTP.setheader(res, "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS")
            HTTP.setheader(res, "Access-Control-Allow-Headers" => allow_headers)
            HTTP.setheader(res, "Access-Control-Allow-Credentials" => "true")
            return res
        catch e
            @error "Handler error: $e"
            res = HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error")))
            HTTP.setheader(res, "Access-Control-Allow-Origin" => origin)
            return res
        end
    end
end

function setup_algofi_routes!(router)
    # Explicit CORS preflight handlers (wildcard route in HTTP.jl can be unreliable for deep paths on some versions)
    preflight = req -> add_cors_headers(HTTP.Response(204, ""))
    HTTP.register!(router, "OPTIONS", "/api/v1/auth/wallet", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/user/profile", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/user/performance", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/user/portfolio", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/user/transactions", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/market/prices", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/strategies", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/ai/recommend", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/arbitrage/opportunities", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/trading/transaction", preflight)
    # Newly added preflight routes for previously failing endpoints
    HTTP.register!(router, "OPTIONS", "/api/v1/trading/opportunities", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/user/strategies", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/strategies", preflight)  # ensure duplicate is harmless but explicit
    HTTP.register!(router, "OPTIONS", "/api/v1/strategies/*/tracking", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/strategies/*/simulate", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/stake/investments", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/stake/history", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/stake/strategies", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/ai/strategy/recommend", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/ai/strategy/validate", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/ai/protocols", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/ai/transaction/create", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/recovery/investments", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/recovery/withdraw", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/recovery/emergency", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/recovery/complete", preflight)
    HTTP.register!(router, "OPTIONS", "/api/v1/recovery/status", preflight)
    # Fallback catch-all (best-effort)
    HTTP.register!(router, "OPTIONS", "/*", preflight)
    
    # User authentication and profile endpoints
    HTTP.register!(router, "POST", "/api/v1/auth/wallet", handle_wallet_auth)
    HTTP.register!(router, "GET", "/api/v1/user/profile", handle_get_user_profile)
    HTTP.register!(router, "PUT", "/api/v1/user/profile", handle_update_user_profile)
    
    # Performance and analytics endpoints
    HTTP.register!(router, "GET", "/api/v1/user/performance", handle_get_user_performance)
    HTTP.register!(router, "GET", "/api/v1/user/portfolio", handle_get_user_portfolio)
    HTTP.register!(router, "GET", "/api/v1/user/transactions", handle_get_user_transactions)
    
    # Strategy management endpoints
    HTTP.register!(router, "GET", "/api/v1/user/strategies", handle_get_user_strategies)
    HTTP.register!(router, "POST", "/api/v1/user/strategies", handle_create_user_strategy)
    HTTP.register!(router, "PUT", "/api/v1/user/strategies/:id", handle_update_user_strategy)
    HTTP.register!(router, "DELETE", "/api/v1/user/strategies/:id", handle_delete_user_strategy)
    
    # Trading endpoints
    HTTP.register!(router, "POST", "/api/v1/trading/transaction", handle_log_transaction)
    HTTP.register!(router, "GET", "/api/v1/trading/opportunities", handle_get_arbitrage_opportunities)
    
    # Market data endpoints
    HTTP.register!(router, "GET", "/api/v1/market/data", handle_get_market_data)
    HTTP.register!(router, "GET", "/api/v1/market/prices", handle_get_current_prices)
    
    # Swarm intelligence endpoints
    HTTP.register!(router, "GET", "/api/v1/swarm/status", get_swarm_status)
    HTTP.register!(router, "GET", "/api/v1/swarm/agents", get_swarm_agents)
    HTTP.register!(router, "POST", "/api/v1/swarm/start", start_swarm)
    HTTP.register!(router, "POST", "/api/v1/swarm/stop", stop_swarm)
    HTTP.register!(router, "GET", "/api/v1/swarm/metrics", get_swarm_metrics)
    
    # Stake/Investment endpoints
    HTTP.register!(router, "POST", "/api/v1/stake/algo", handle_stake_algo)
    HTTP.register!(router, "POST", "/api/v1/stake/withdraw", handle_withdraw_stake)
    HTTP.register!(router, "GET", "/api/v1/stake/investments", handle_get_investments)
    HTTP.register!(router, "GET", "/api/v1/stake/history", handle_get_transaction_history)
    HTTP.register!(router, "GET", "/api/v1/stake/strategies", handle_get_ai_strategies)
    HTTP.register!(router, "GET", "/api/v1/stake/balance", handle_get_stakeable_amount)
    
    # AI Strategy Recommendation endpoints
    HTTP.register!(router, "POST", "/api/v1/ai/strategy/recommend", handle_get_ai_recommendation)
    HTTP.register!(router, "POST", "/api/v1/ai/strategy/validate", handle_validate_protocol_safety)
    HTTP.register!(router, "GET", "/api/v1/ai/protocols", handle_get_available_protocols)
    HTTP.register!(router, "POST", "/api/v1/ai/transaction/create", handle_create_protocol_transaction)
    
    # Real DeFi Protocol Transaction endpoints 
    HTTP.register!(router, "POST", "/api/v1/defi/transaction/create-deposit", handle_create_protocol_deposit_tx)
    HTTP.register!(router, "POST", "/api/v1/defi/transaction/create-withdraw", handle_create_protocol_withdraw_tx)
    HTTP.register!(router, "POST", "/api/v1/defi/transaction/submit", handle_submit_protocol_transaction)
    HTTP.register!(router, "POST", "/api/v1/defi/transaction/confirm", handle_wait_protocol_confirmation)
    HTTP.register!(router, "POST", "/api/v1/defi/transaction/complete", handle_complete_protocol_transaction)
    
    # Fund Recovery & Security System endpoints
    HTTP.register!(router, "GET", "/api/v1/recovery/investments", handle_get_user_active_investments)
    HTTP.register!(router, "POST", "/api/v1/recovery/withdraw", handle_create_recovery_withdrawal)
    HTTP.register!(router, "POST", "/api/v1/recovery/emergency", handle_emergency_fund_recovery)
    HTTP.register!(router, "POST", "/api/v1/recovery/complete", handle_complete_fund_recovery)
    HTTP.register!(router, "GET", "/api/v1/recovery/status", handle_get_recovery_status)
    
    # Strategy Management endpoints
    HTTP.register!(router, "GET", "/api/v1/strategies", handle_get_ai_strategies)
    HTTP.register!(router, "PUT", "/api/v1/strategies/*/performance", handle_update_strategy_performance)
    
    # Real-time P&L Tracking endpoints
    HTTP.register!(router, "GET", "/api/v1/strategies/*/tracking", handle_get_strategy_tracking)
    HTTP.register!(router, "POST", "/api/v1/strategies/*/simulate", handle_simulate_strategy_performance)
end

function run_server(host::AbstractString="127.0.0.1", port::Integer=8052)
    try
        router = HTTP.Router()
        # basic health check (with CORS for frontend availability)
        HTTP.register!(router, "GET", "/ping", req -> begin
            add_cors_headers(HTTP.Response(200, "pong"))
        end)

        # Simple test endpoint (unified CORS helper)
        HTTP.register!(router, "GET", "/test", function(req)
            response = HTTP.Response(200, JSON3.write(Dict("status" => "OK")))
            HTTP.setheader(response, "Content-Type" => "application/json")
            return add_cors_headers(response)
        end)
        
    setup_algofi_routes!(router)

    # NOTE: Per-endpoint CORS is currently applied via add_cors_headers.
    # If you prefer a global middleware approach, uncomment the line below
    # to wrap the router so every response (including errors) gets CORS automatically.
    # router = HTTP.Router(cors_middleware(router))  # <-- optional global CORS
        @info "AlgoFi API starting" host port
        # Warm the price cache once at startup (non-blocking spawn)
        try
            @info "Warming initial price cache..."
            @spawn _refresh_price_cache!()
        catch e
            @warn "Initial price cache warm failed" error=e
        end
        
        # Simple server without complex middleware
        server = HTTP.serve!(router, host, port; 
            readtimeout=30,      # Increased timeout
            writetimeout=30,     # Increased timeout  
            reuseaddr=true,      # Allow port reuse
            verbose=true         # Enable verbose logging to debug
        )
        SERVER[] = server
        wait(server)
    catch ex
        @error "AlgoFi API server error" exception=(ex, catch_backtrace())
        rethrow()
    end
end

# Authentication handlers
function handle_wallet_auth(req::HTTP.Request)
    try
        body = @with_timing (:parse_wallet_auth_body) JSON3.read(String(req.body))
        wallet_address = String(body.wallet_address)
        raw_account_info = get(body, :account_info, Dict{String, Any}())
        account_info = JSON3.read(JSON3.write(raw_account_info), Dict{String, Any})
        
        # Validate wallet address format
        if !isvalid_algorand_address(wallet_address)
            return add_cors_headers(HTTP.Response(400, JSON3.write(Dict(
                "error" => "Invalid Algorand wallet address"
            ))))
        end
        
        # Create or update user
        user = @with_timing (:create_user) AlgoFiUsers.create_user(wallet_address, account_info)
        
        # Normalize datetime fields for JSON serialization
        created_at_val = isa(user.created_at, TimeZones.ZonedDateTime) ? string(user.created_at) : user.created_at
        last_login_val = user.last_login === nothing ? nothing : (isa(user.last_login, TimeZones.ZonedDateTime) ? string(user.last_login) : user.last_login)

        response = HTTP.Response(200, JSON3.write(Dict(
            "user" => Dict(
                "wallet_address" => user.wallet_address,
                "created_at" => created_at_val,
                "last_login" => last_login_val,
                "settings" => user.settings,
                "account_info" => get(user.settings, "account_info", Dict{String, Any}())
            ),
            "message" => "Authentication successful"
        )))
        return add_cors_headers(response)
        
    catch e
        @error "Wallet auth error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict(
            "error" => "Authentication failed"
        ))))
    end
end

function handle_get_user_profile(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        
        user = AlgoFiUsers.get_user(wallet_address)
        if user === nothing
            return add_cors_headers(HTTP.Response(404, JSON3.write(Dict("error" => "User not found"))))
        end
        
        response = HTTP.Response(200, JSON3.write(Dict(
            "wallet_address" => user.wallet_address,
            "created_at" => isa(user.created_at, TimeZones.ZonedDateTime) ? string(user.created_at) : user.created_at,
            "last_login" => user.last_login === nothing ? nothing : (isa(user.last_login, TimeZones.ZonedDateTime) ? string(user.last_login) : user.last_login),
            "settings" => user.settings,
            "account_info" => get(user.settings, "account_info", Dict{String, Any}())
        )))
        return add_cors_headers(response)
        
    catch e
        @error "Get user profile error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_update_user_profile(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        
        body = JSON3.read(String(req.body))
        
        if haskey(body, :account_info)
            AlgoFiUsers.update_user_account_info(wallet_address, body.account_info)
        end
        response = HTTP.Response(200, JSON3.write(Dict("message" => "Profile updated successfully")))
        return add_cors_headers(response)
        
    catch e
        @error "Update user profile error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

# Performance handlers
function handle_get_user_performance(req::HTTP.Request)
    try
        @with_timing (:user_performance_total) begin
            wallet_address = get_wallet_from_auth(req)
            if wallet_address === nothing
                return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
            end
            
            # Parse query parameters
            query_params = HTTP.queryparams(HTTP.URI(req.target))
            days = parse(Int, get(query_params, "days", "30"))
            
            performance = @with_timing (:get_performance_query) AlgoFiUsers.get_user_performance(wallet_address, days)
            
            response = HTTP.Response(200, JSON3.write(Dict(
                "performance" => [Dict(
                    "date" => p.date,
                    "total_invested_algo" => p.total_invested_algo,
                    "current_value_algo" => p.current_value_algo,
                    "total_pnl_algo" => p.total_pnl_algo,
                    "win_rate" => p.win_rate,
                    "total_trades" => p.total_trades,
                    "successful_trades" => p.successful_trades
                ) for p in performance]
            )))
            return add_cors_headers(response)
        end
    catch e
        @error "Get user performance error: $(e)" exception=(e, catch_backtrace())
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_get_user_portfolio(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        
        snapshot = AlgoFiUsers.get_portfolio_snapshot(wallet_address)
        
        if snapshot === nothing
            # Return empty portfolio if no snapshot exists
            response = HTTP.Response(200, JSON3.write(Dict(
                "total_value_usd" => 0.0,
                "total_algo" => 0.0,
                "assets" => Dict{String, Any}(),
                "performance_metrics" => Dict{String, Any}(),
                "snapshot_date" => now()
            )))
            return add_cors_headers(response)
        end
        
        response = HTTP.Response(200, JSON3.write(snapshot))
        return add_cors_headers(response)
        
    catch e
        @error "Get user portfolio error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_get_user_transactions(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        
        query_params = HTTP.queryparams(HTTP.URI(req.target))
        limit = parse(Int, get(query_params, "limit", "100"))
        
        transactions = AlgoFiUsers.get_user_transactions(wallet_address, limit)
        
        response = HTTP.Response(200, JSON3.write(Dict(
            "transactions" => [Dict(
                "id" => t.id,
                "strategy_id" => t.strategy_id,
                "transaction_type" => t.transaction_type,
                "asset_id" => t.asset_id,
                "amount" => t.amount,
                "price" => t.price,
                "pnl_amount" => t.pnl_amount,
                "transaction_hash" => t.transaction_hash,
                "timestamp" => (isa(t.timestamp, TimeZones.ZonedDateTime) ? string(t.timestamp) : t.timestamp),
                "metadata" => t.metadata
            ) for t in transactions]
        )))
        
        return add_cors_headers(response)
        
    catch e
        @error "Get user transactions error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

# Strategy management handlers
function handle_get_user_strategies(req::HTTP.Request)
    try
        # Skip authentication for testing
        @info "Handling user strategies request"
        
        # Return simple test data
        response_data = Dict(
            "strategies" => [
                Dict(
                    "id" => 1,
                    "strategy_name" => "Test Strategy",
                    "strategy_type" => "arbitrage",
                    "settings" => Dict(),
                    "allocated_amount" => 100.0,
                    "is_active" => true,
                    "performance_score" => 0.0,
                    "current_pnl" => 0.0,
                    "created_at" => "2024-01-01T00:00:00Z"
                )
            ]
        )
        
        response = HTTP.Response(200, JSON3.write(response_data))
        HTTP.setheader(response, "Content-Type" => "application/json")
        
        @info "Returning user strategies response"
        return add_cors_headers(response)
        
    catch e
        @error "Get user strategies error: $(e)"
        error_response = HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error")))
        HTTP.setheader(error_response, "Content-Type" => "application/json")
        return add_cors_headers(error_response)
    end
end

function handle_create_user_strategy(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        
        body = JSON3.read(String(req.body))
        @info "Received create strategy request" body=body
        
        # Extract and convert settings properly with recursive conversion
        settings_raw = get(body, "settings", nothing)
        settings = if settings_raw === nothing
            Dict{String, Any}()
        else
            # Convert JSON3.Object to Dict recursively
            json_to_dict(settings_raw)
        end
        
        @info "Processed settings" settings=settings
        
        strategy = AlgoFiUsers.create_user_strategy(
            wallet_address,
            String(body["strategy_name"]),
            String(body["strategy_type"]),
            settings,
            Float64(get(body, "allocated_amount", 0.0))
        )
        
        response = HTTP.Response(201, JSON3.write(Dict(
            "strategy" => Dict(
                "id" => strategy.id,
                "strategy_name" => strategy.strategy_name,
                "strategy_type" => strategy.strategy_type,
                "settings" => strategy.settings,
                "allocated_amount" => strategy.allocated_amount,
                "is_active" => strategy.is_active,
                "performance_score" => strategy.performance_score,
                "current_pnl" => strategy.current_pnl,
                "created_at" => strategy.created_at
            ),
            "message" => "Strategy created successfully"
        )))
        
        return add_cors_headers(response)
        
    catch e
        @error "Create user strategy error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_update_user_strategy(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end

        # Extract :id from path
        path = String(req.target)
        m = match(r"/api/v1/user/strategies/(\d+)", path)
        if m === nothing
            return add_cors_headers(HTTP.Response(400, JSON3.write(Dict("error" => "Invalid strategy id"))))
        end
        id = parse(Int, m.captures[1])

        body = JSON3.read(String(req.body))

        updated = AlgoFiUsers.update_user_strategy(
            wallet_address,
            id;
            strategy_name = get(body, :strategy_name, nothing),
            strategy_type = get(body, :strategy_type, nothing),
            settings      = get(body, :settings, nothing),
            allocated_amount = get(body, :allocated_amount, nothing),
            is_active     = get(body, :is_active, nothing)
        )

        response = HTTP.Response(200, JSON3.write(Dict(
            "strategy" => Dict(
                "id" => updated.id,
                "strategy_name" => updated.strategy_name,
                "strategy_type" => updated.strategy_type,
                "settings" => updated.settings,
                "allocated_amount" => updated.allocated_amount,
                "is_active" => updated.is_active,
                "performance_score" => updated.performance_score,
                "current_pnl" => updated.current_pnl,
                "created_at" => updated.created_at
            ),
            "message" => "Strategy updated successfully"
        )))
        
        return add_cors_headers(response)
    catch e
        @error "Update user strategy error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_delete_user_strategy(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end

        path = String(req.target)
        m = match(r"/api/v1/user/strategies/(\d+)", path)
        if m === nothing
            return add_cors_headers(HTTP.Response(400, JSON3.write(Dict("error" => "Invalid strategy id"))))
        end
        id = parse(Int, m.captures[1])

        # soft delete: set is_active = false
        _ = AlgoFiUsers.update_user_strategy(wallet_address, id; is_active=false)
        
        response = HTTP.Response(200, JSON3.write(Dict("message" => "Strategy deleted")))
        return add_cors_headers(response)
    catch e
        @error "Delete user strategy error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

# Utility functions
function get_wallet_from_auth(req::HTTP.Request)::Union{String, Nothing}
    # Extract wallet address from Authorization header or query params
    auth_header = HTTP.header(req, "Authorization", "")
    
    if startswith(auth_header, "Wallet ")
        return strip(auth_header[8:end])
    end
    
    query_params = HTTP.queryparams(HTTP.URI(req.target))
    return get(query_params, "wallet", nothing)
end

function isvalid_algorand_address(address::String)::Bool
    # Basic Algorand address validation (58 characters, base32)
    return length(address) == 58 && all(c -> c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", address)
end

function handle_get_arbitrage_opportunities(req::HTTP.Request)
    try
        @with_timing (:arb_opps_total) begin
            @info "Fetching arbitrage opportunities from database..."
            query = """
                SELECT 
                    id, asset_pair, dex_1, dex_2, price_1, price_2, 
                    profit_percentage, min_trade_amount, max_trade_amount,
                    is_active, expires_at, created_at
                FROM arbitrage_opportunities 
                WHERE is_active = true 
                    AND expires_at > NOW()
                ORDER BY profit_percentage DESC, created_at DESC
                LIMIT 20
            """
            result = @with_timing (:arb_query) execute_query(query)
            opportunities = Vector{Dict{String, Any}}()
            for row in result
                push!(opportunities, Dict(
                    "id" => row[1],
                    "asset_pair" => row[2],
                    "dex_1" => row[3],
                    "dex_2" => row[4],
                    "price_1" => try parse(Float64, string(row[5])) catch; missing end,
                    "price_2" => try parse(Float64, string(row[6])) catch; missing end,
                    "profit_percentage" => try parse(Float64, string(row[7])) catch; missing end,
                    "min_trade_amount" => try parse(Float64, string(row[8])) catch; missing end,
                    "max_trade_amount" => try parse(Float64, string(row[9])) catch; missing end,
                    "is_active" => row[10],
                    "expires_at" => string(row[11]),
                    "created_at" => string(row[12])
                ))
            end
            if isempty(opportunities)
                @info "No arbitrage opportunities found in database"
                return add_cors_headers(HTTP.Response(200, JSON3.write(Dict("opportunities" => []))))
            end
            @info "Returning $(length(opportunities)) arbitrage opportunities"
            return add_cors_headers(HTTP.Response(200, JSON3.write(Dict("opportunities" => opportunities))))
        end
    catch e
        @error "Get arbitrage opportunities error: $(e)"
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict(
            "error" => "Internal server error",
            "details" => "Failed to fetch arbitrage opportunities"
        ))))
    end
end

function handle_get_market_data(req::HTTP.Request)
    try
        @info "Fetching market data from database..."
        
        # Use optimized query execution
        query = """
            SELECT DISTINCT 
                asset_pair as asset_id,
                price,
                volume_24h,
                COALESCE(price * volume_24h, 0) as market_cap,
                0.0 as price_change_24h
            FROM price_feeds 
            WHERE last_updated >= NOW() - INTERVAL '1 hour'
            ORDER BY last_updated DESC
        """
        
        result = execute_query(query)
        
        market_data = Dict()
        for row in result
            asset = String(row[1])
            market_data[asset] = Dict(
                "price_usd" => Float64(row[2]),
                "change_24h" => Float64(row[5]),
                "volume_24h" => row[3] !== nothing ? Float64(row[3]) : 0.0,
                "market_cap" => row[4] !== nothing ? Float64(row[4]) : 0.0
            )
        end
        
        # If no data found, return empty structure
        if isempty(market_data)
            @info "No recent market data found in database"
            market_data = Dict("message" => "No recent market data available")
        end

        response = HTTP.Response(200, JSON3.write(market_data))
        return add_cors_headers(response)
        
    catch e
        @error "Get market data error: $(e)"
        error_response = HTTP.Response(500, JSON3.write(Dict(
            "error" => "Internal server error",
            "details" => "Failed to fetch market data"
        )))
        return add_cors_headers(error_response)
    end
end

function handle_get_current_prices(req::HTTP.Request)
    try
        @with_timing (:prices_handler_total) begin
            _maybe_refresh_cache_async()
            local snapshot
            lock(PRICE_CACHE_LOCK) do
                snapshot = deepcopy(PRICE_CACHE[])
            end
            if isempty(snapshot)
                # First request before cache fill – return empty quickly
                response = HTTP.Response(200, JSON3.write(Dict("prices" => Dict())))
                return add_cors_headers(response)
            else
                response = HTTP.Response(200, JSON3.write(Dict("prices" => snapshot["prices"])))
                return add_cors_headers(response)
            end
        end
        
    catch e
        @error "Get current prices error: $(e)"
        error_response = HTTP.Response(500, JSON3.write(Dict(
            "error" => "Internal server error",
            "details" => "Failed to fetch price data"
        )))
        return add_cors_headers(error_response)
    end
end

function handle_log_transaction(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        body = JSON3.read(String(req.body))
        # Map possible field name variants
        tx_type = get(body, :transaction_type, get(body, :type, "unknown"))
        asset_id = get(body, :asset_id, nothing)
        asset_symbol = get(body, :asset_symbol, nothing)
        network = get(body, :network, nothing)
        amount = get(body, :amount, nothing)
        price = get(body, :price, nothing)
        slippage = get(body, :slippage, nothing)
        gas_fee = get(body, :gas_fee, nothing)
        nonce = get(body, :nonce, nothing)
        tx_hash = get(body, :tx_hash, get(body, :transaction_hash, nothing))
        status = get(body, :status, "pending")
        error_message = get(body, :error_message, nothing)

        AlgoFiUsers.log_trading_transaction(
            wallet_address,
            get(body, :strategy_id, nothing),
            tx_type,
            asset_id,
            asset_symbol,
            network,
            amount,
            price,
            slippage,
            gas_fee,
            nonce,
            tx_hash,
            status,
            error_message
        )
        return add_cors_headers(HTTP.Response(201, JSON3.write(Dict("message" => "Transaction logged successfully"))))
    catch e
        @error "Log transaction error: $(e)" exception=(e, catch_backtrace())
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict(
            "error" => "Internal server error",
            "details" => "Failed to log transaction"
        ))))
    end
end

# Restored / fixed stake handler (was partially overwritten in previous malformed patch)
function handle_stake_algo(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
        end
        body = JSON3.read(String(req.body))
        amount = get(body, :amount, nothing)
        ai_strategy_id = get(body, :ai_strategy_id, nothing)
        result = StakeAPI.stake_algo(wallet_address, amount, ai_strategy_id)
        status_code = result["status"] == "success" ? 200 : 400
        return add_cors_headers(HTTP.Response(status_code, JSON3.write(result)))
    catch e
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => string(e)))))
    end
end

function handle_withdraw_stake(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        investment_id = body.investment_id
        amount = body.amount
        
        result = StakeAPI.withdraw_stake(wallet_address, investment_id, amount)
        
        if result["status"] == "success"
            return HTTP.Response(200, JSON3.write(result))
        else
            return HTTP.Response(400, JSON3.write(result))
        end
    catch e
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_get_investments(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        result = StakeAPI.get_user_investments(wallet_address)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_get_transaction_history(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        # Query parametresi olarak limit al
        uri = HTTP.URI(req.url)
        query_params = HTTP.URIs.queryparams(uri)
        limit = haskey(query_params, "limit") ? parse(Int64, query_params["limit"]) : 50
        
        result = StakeAPI.get_transaction_history(wallet_address, limit)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_get_stakeable_amount(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        result = StakeAPI.calculate_stakeable_amount(wallet_address)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

# AI Strategy Recommendation Handler Functions

function handle_get_ai_recommendation(req::HTTP.Request)
    try
        @with_timing (:ai_recommendation_total) begin
            wallet_address = get_wallet_from_auth(req)
            if wallet_address === nothing
                return add_cors_headers(HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized"))))
            end
            
            body = JSON3.read(String(req.body))
            
            # Validate required parameters
            if !haskey(body, :amount_microalgo)
                return add_cors_headers(HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required"))))
            end
            
            amount_microalgo = Int64(body.amount_microalgo)
            risk_preference = get(body, :risk_preference, "medium")  # Default to medium risk
            
            # Validate risk preference
            if !(risk_preference in ["low", "medium", "high"])
                return add_cors_headers(HTTP.Response(400, JSON3.write(Dict("error" => "risk_preference must be 'low', 'medium', or 'high'"))))
            end
            
            result = @with_timing (:ai_strategy_query) StakeAPI.get_ai_strategy_recommendation(wallet_address, amount_microalgo, risk_preference)
            
            return add_cors_headers(HTTP.Response(200, JSON3.write(result)))
        end
    catch e
        @error "AI recommendation error: $(e)" exception=(e, catch_backtrace())
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => string(e)))))
    end
end

function handle_validate_protocol_safety(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        
        # Validate required parameters  
        if !haskey(body, :protocol_name)
            return HTTP.Response(400, JSON3.write(Dict("error" => "protocol_name is required")))
        end
        
        if !haskey(body, :amount_microalgo)
            return HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required")))
        end
        
        protocol_name = String(body.protocol_name)
        amount_microalgo = Int64(body.amount_microalgo)
        
        result = StakeAPI.validate_protocol_safety_endpoint(protocol_name, amount_microalgo)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Protocol validation error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_get_available_protocols(req::HTTP.Request)
    try
        result = StakeAPI.get_available_protocols()
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Get protocols error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_create_protocol_transaction(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :protocol_name)
            return HTTP.Response(400, JSON3.write(Dict("error" => "protocol_name is required")))
        end
        
        if !haskey(body, :amount_microalgo) 
            return HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required")))
        end
        
        protocol_name = String(body.protocol_name)
        amount_microalgo = Int64(body.amount_microalgo)
        algorand_tx_id = get(body, :algorand_tx_id, "")  # Optional transaction ID
        
        result = StakeAPI.create_protocol_transaction_endpoint(wallet_address, protocol_name, amount_microalgo, algorand_tx_id)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Create protocol transaction error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

# Real DeFi Protocol Transaction Handler Functions

function handle_create_protocol_deposit_tx(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :protocol_name)
            return HTTP.Response(400, JSON3.write(Dict("error" => "protocol_name is required")))
        end
        
        if !haskey(body, :amount_microalgo)
            return HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required")))
        end
        
        protocol_name = String(body.protocol_name)
        amount_microalgo = Int64(body.amount_microalgo)
        
        result = StakeAPI.create_protocol_deposit_tx_endpoint(protocol_name, wallet_address, amount_microalgo)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Create protocol deposit transaction error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_create_protocol_withdraw_tx(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :protocol_name)
            return HTTP.Response(400, JSON3.write(Dict("error" => "protocol_name is required")))
        end
        
        if !haskey(body, :amount_microalgo)
            return HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required")))
        end
        
        protocol_name = String(body.protocol_name)
        amount_microalgo = Int64(body.amount_microalgo)
        
        result = StakeAPI.create_protocol_withdraw_tx_endpoint(protocol_name, wallet_address, amount_microalgo)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Create protocol withdraw transaction error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_submit_protocol_transaction(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :signed_transaction)
            return HTTP.Response(400, JSON3.write(Dict("error" => "signed_transaction is required")))
        end
        
        signed_transaction = String(body.signed_transaction)
        
        result = StakeAPI.submit_protocol_transaction_endpoint(signed_transaction)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Submit protocol transaction error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_wait_protocol_confirmation(req::HTTP.Request)
    try
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :tx_id)
            return HTTP.Response(400, JSON3.write(Dict("error" => "tx_id is required")))
        end
        
        tx_id = String(body.tx_id)
        timeout_seconds = get(body, :timeout_seconds, 30)  # Default 30 seconds
        
        result = StakeAPI.wait_protocol_confirmation_endpoint(tx_id, timeout_seconds)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Wait protocol confirmation error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_complete_protocol_transaction(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        # Validate required parameters
        if !haskey(body, :protocol_name)
            return HTTP.Response(400, JSON3.write(Dict("error" => "protocol_name is required")))
        end
        
        if !haskey(body, :amount_microalgo)
            return HTTP.Response(400, JSON3.write(Dict("error" => "amount_microalgo is required")))
        end
        
        if !haskey(body, :signed_transaction)
            return HTTP.Response(400, JSON3.write(Dict("error" => "signed_transaction is required")))
        end
        
        protocol_name = String(body.protocol_name)
        amount_microalgo = Int64(body.amount_microalgo)
        signed_transaction = String(body.signed_transaction)
        
        result = StakeAPI.complete_protocol_transaction_endpoint(wallet_address, protocol_name, amount_microalgo, signed_transaction)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Complete protocol transaction error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

# Fund Recovery & Security System Handler Functions

function handle_get_user_active_investments(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        result = StakeAPI.get_user_active_investments_endpoint(wallet_address)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Get active investments error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_create_recovery_withdrawal(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        if !haskey(body, :investment_id)
            return HTTP.Response(400, JSON3.write(Dict("error" => "investment_id is required")))
        end
        
        investment_id = Int64(body.investment_id)
        
        result = StakeAPI.create_recovery_withdrawal_endpoint(wallet_address, investment_id)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Create recovery withdrawal error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_emergency_fund_recovery(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        if !haskey(body, :investment_id)
            return HTTP.Response(400, JSON3.write(Dict("error" => "investment_id is required")))
        end
        
        investment_id = Int64(body.investment_id)
        override_time_lock = get(body, :override_time_lock, false)
        
        # Log emergency recovery attempt
        @warn "Emergency fund recovery requested" wallet=wallet_address investment_id=investment_id override=override_time_lock
        
        result = StakeAPI.emergency_fund_recovery_endpoint(wallet_address, investment_id, override_time_lock)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Emergency fund recovery error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_complete_fund_recovery(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        body = JSON3.read(String(req.body))
        
        if !haskey(body, :investment_id)
            return HTTP.Response(400, JSON3.write(Dict("error" => "investment_id is required")))
        end
        
        if !haskey(body, :tx_id)
            return HTTP.Response(400, JSON3.write(Dict("error" => "tx_id is required")))
        end
        
        if !haskey(body, :confirmation_result)
            return HTTP.Response(400, JSON3.write(Dict("error" => "confirmation_result is required")))
        end
        
        investment_id = Int64(body.investment_id)
        tx_id = String(body.tx_id)
        confirmation_result = body.confirmation_result
        
        result = StakeAPI.complete_fund_recovery_endpoint(wallet_address, investment_id, tx_id, confirmation_result)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Complete fund recovery error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

function handle_get_recovery_status(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        result = StakeAPI.get_recovery_status_endpoint(wallet_address)
        
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Get recovery status error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

# Strategy endpoints
function handle_get_ai_strategies(req::HTTP.Request)
    try
        @with_timing (:ai_strategies_total) begin
            result = @with_timing (:ai_strategies_query) StakeAPI.get_real_ai_strategies()
            return add_cors_headers(HTTP.Response(200, JSON3.write(result)))
        end
    catch e
        @error "Error getting AI strategies" error=string(e) exception=(e, catch_backtrace())
        return add_cors_headers(HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error"))))
    end
end

function handle_update_strategy_performance(req::HTTP.Request)
    try
        # Extract strategy ID from path manually
        path_parts = split(req.target, "/")
        
        # Find strategies index
        strategies_idx = findfirst(x -> x == "strategies", path_parts)
        if strategies_idx === nothing || strategies_idx + 1 > length(path_parts)
            return HTTP.Response(400, JSON3.write(Dict("error" => "Invalid strategy ID")))
        end
        
        strategy_id_str = path_parts[strategies_idx + 1]
        strategy_id = parse(Int64, strategy_id_str)
        body = JSON3.read(String(req.body))
        
        result = StakeAPI.update_strategy_performance(strategy_id, body)
        return HTTP.Response(200, JSON3.write(result))
    catch e
        @error "Error updating strategy performance" error=string(e)
        return HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error")))
    end
end

# Real-time P&L Tracking handlers
function handle_get_strategy_tracking(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        # Extract strategy ID from path
        path_parts = split(req.target, "/")
        strategies_idx = findfirst(x -> x == "strategies", path_parts)
        if strategies_idx === nothing || strategies_idx + 1 > length(path_parts)
            return HTTP.Response(400, JSON3.write(Dict("error" => "Invalid strategy ID")))
        end
        
        strategy_id = parse(Int64, path_parts[strategies_idx + 1])
        
        conn = get_connection()
        if conn === nothing
            return HTTP.Response(503, JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Get recent performance tracking data
        query = """
            SELECT 
                timestamp, allocated_amount, current_value, pnl_amount, 
                pnl_percentage, total_trades, successful_trades, win_rate
            FROM strategy_performance_tracking 
            WHERE strategy_id = \$1 AND wallet_address = \$2
            ORDER BY timestamp DESC
            LIMIT 100
        """
        
        result = execute(conn, query, [strategy_id, wallet_address])
        tracking_data = []
        
        for row in result
            push!(tracking_data, Dict(
                "timestamp" => string(row[1]),
                "allocated_amount" => Float64(row[2]),
                "current_value" => Float64(row[3]),
                "pnl_amount" => Float64(row[4]),
                "pnl_percentage" => Float64(row[5]),
                "total_trades" => row[6],
                "successful_trades" => row[7],
                "win_rate" => Float64(row[8])
            ))
        end
        
        close(conn)
        return HTTP.Response(200, JSON3.write(Dict("tracking" => tracking_data)))
        
    catch e
        @error "Get strategy tracking error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error")))
    end
end

function handle_simulate_strategy_performance(req::HTTP.Request)
    try
        wallet_address = get_wallet_from_auth(req)
        if wallet_address === nothing
            return HTTP.Response(401, JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        # Extract strategy ID from path
        path_parts = split(req.target, "/")
        strategies_idx = findfirst(x -> x == "strategies", path_parts)
        if strategies_idx === nothing || strategies_idx + 1 > length(path_parts)
            return HTTP.Response(400, JSON3.write(Dict("error" => "Invalid strategy ID")))
        end
        
        strategy_id = parse(Int64, path_parts[strategies_idx + 1])
        
        conn = get_connection()
        if conn === nothing
            return HTTP.Response(503, JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Get strategy details
        strategy_query = """
            SELECT strategy_type, allocated_amount, settings
            FROM user_strategies
            WHERE id = \$1 AND wallet_address = \$2 AND is_active = true
        """
        
        strategy_result = execute(conn, strategy_query, [strategy_id, wallet_address])
        
        if isempty(strategy_result)
            close(conn)
            return HTTP.Response(404, JSON3.write(Dict("error" => "Strategy not found")))
        end
        
        strategy_row = first(strategy_result)
        strategy_type = strategy_row[1]
        allocated_amount = Float64(strategy_row[2])
        settings = JSON3.read(strategy_row[3], Dict{String, Any})
        
        # Get real market prices from price_feeds table
        price_query = """
            SELECT asset_pair, dex_name, price, volume_24h
            FROM price_feeds
            WHERE last_updated > NOW() - INTERVAL '1 hour'
        """
        
        price_result = execute(conn, price_query)
        
        # Transform price data to structured format
        market_prices = Dict{String, Dict{String, Dict{String, Float64}}}()
        for row in price_result
            asset_pair = String(row[1])
            dex_name = String(row[2])
            price = Float64(row[3])
            volume = row[4] !== nothing ? Float64(row[4]) : 0.0
            
            if !haskey(market_prices, asset_pair)
                market_prices[asset_pair] = Dict{String, Dict{String, Float64}}()
            end
            
            market_prices[asset_pair][dex_name] = Dict(
                "price" => price,
                "volume" => volume
            )
        end
        
        # Simulate performance based on strategy type with real market data
        simulated_pnl = simulate_strategy_pnl_with_market_data(strategy_type, allocated_amount, settings, market_prices)
        
        # Insert tracking record
        tracking_query = """
            INSERT INTO strategy_performance_tracking 
                (strategy_id, wallet_address, allocated_amount, current_value, 
                 pnl_amount, pnl_percentage, total_trades, successful_trades, win_rate)
            VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
            RETURNING timestamp
        """
        
        current_value = allocated_amount + simulated_pnl["pnl_amount"]
        pnl_percentage = (simulated_pnl["pnl_amount"] / allocated_amount) * 100
        
        tracking_result = execute(conn, tracking_query, [
            strategy_id, wallet_address, allocated_amount, current_value,
            simulated_pnl["pnl_amount"], pnl_percentage, 
            simulated_pnl["total_trades"], simulated_pnl["successful_trades"],
            simulated_pnl["win_rate"]
        ])
        
        timestamp = first(tracking_result)[1]
        
        # Update user_strategies current_pnl
        update_query = """
            UPDATE user_strategies 
            SET current_pnl = \$2, performance_score = \$3
            WHERE id = \$1
        """
        
        execute(conn, update_query, [strategy_id, simulated_pnl["pnl_amount"], simulated_pnl["win_rate"] / 100])
        
        close(conn)
        
        return HTTP.Response(200, JSON3.write(Dict(
            "timestamp" => string(timestamp),
            "allocated_amount" => allocated_amount,
            "current_value" => current_value,
            "pnl_amount" => simulated_pnl["pnl_amount"],
            "pnl_percentage" => pnl_percentage,
            "total_trades" => simulated_pnl["total_trades"],
            "successful_trades" => simulated_pnl["successful_trades"],
            "win_rate" => simulated_pnl["win_rate"]
        )))
        
    catch e
        @error "Simulate strategy performance error: $(e)"
        return HTTP.Response(500, JSON3.write(Dict("error" => "Internal server error")))
    end
end

# Strategy performance simulation logic with real market data
function simulate_strategy_pnl_with_market_data(strategy_type::String, allocated_amount::Float64, settings::Dict{String, Any}, market_prices::Dict)
    if strategy_type == "arbitrage"
        return calculate_arbitrage_pnl_with_real_data(allocated_amount, settings, market_prices)
    elseif strategy_type == "yield_farming"
        return calculate_yield_farming_pnl_with_real_data(allocated_amount, settings, market_prices)
    elseif strategy_type == "market_making"
        return calculate_market_making_pnl_with_real_data(allocated_amount, settings, market_prices)
    else
        return simulate_strategy_pnl(strategy_type, allocated_amount, settings)  # Fallback to old method
    end
end

function calculate_arbitrage_pnl_with_real_data(allocated_amount::Float64, settings::Dict, market_prices::Dict)
    total_profit = 0.0
    total_trades = 0
    successful_trades = 0
    
    # Calculate real arbitrage opportunities from price differences
    for (pair, dex_prices) in market_prices
        if length(dex_prices) >= 2
            prices = [data["price"] for data in values(dex_prices)]
            volumes = [data["volume"] for data in values(dex_prices)]
            
            min_price = minimum(prices)
            max_price = maximum(prices)
            min_volume = minimum(volumes)
            
            if max_price > min_price
                # Calculate potential profit percentage
                profit_pct = ((max_price - min_price) / min_price) * 100
                
                if profit_pct > 0.1  # Minimum profitable threshold
                    # Calculate trade size based on available volume
                    max_trade_size = min(allocated_amount * 0.2, min_volume * max_price * 0.1)  # Max 20% allocation, 10% of volume
                    
                    if max_trade_size > 100  # Minimum $100 trade
                        profit = max_trade_size * (profit_pct / 100) * 0.7  # 70% efficiency after fees
                        total_profit += profit
                        total_trades += 1
                        successful_trades += 1
                    end
                end
            end
        end
    end
    
    # Scale based on frequency (assume multiple opportunities per day)
    frequency_multiplier = 1 + rand() * 2  # 1-3x frequency
    daily_profit = total_profit * frequency_multiplier
    daily_trades = Int(ceil(total_trades * frequency_multiplier))
    
    win_rate = total_trades > 0 ? (successful_trades / total_trades * 100) : 0.0
    
    return Dict(
        "pnl_amount" => daily_profit,
        "total_trades" => daily_trades,
        "successful_trades" => Int(ceil(successful_trades * frequency_multiplier)),
        "win_rate" => min(win_rate, 95.0)  # Cap at 95%
    )
end

function calculate_yield_farming_pnl_with_real_data(allocated_amount::Float64, settings::Dict, market_prices::Dict)
    # Get ALGO price for yield calculations
    algo_price = 0.185  # Default
    
    if haskey(market_prices, "ALGO/USDC")
        algo_prices = [data["price"] for data in values(market_prices["ALGO/USDC"])]
        algo_price = length(algo_prices) > 0 ? sum(algo_prices) / length(algo_prices) : 0.185
    end
    
    # Yield farming returns based on market volatility and volume
    total_volume = sum([
        sum([data["volume"] for data in values(dex_prices)])
        for (pair, dex_prices) in market_prices
    ])
    
    # Higher volume generally means better yield opportunities
    volume_factor = min(total_volume / 1000000, 2.0)  # Max 2x multiplier for high volume
    base_apy = 0.08 + (volume_factor - 1) * 0.05  # 8-18% APY based on volume
    
    daily_yield = allocated_amount * (base_apy / 365)
    
    # Add price appreciation/depreciation
    price_change_pct = (algo_price - 0.185) / 0.185 * 100
    price_effect = allocated_amount * (price_change_pct / 100) * 0.1  # 10% exposure to price change
    
    total_pnl = daily_yield + price_effect
    
    return Dict(
        "pnl_amount" => total_pnl,
        "total_trades" => Int(rand(2:5)),  # 2-5 yield claims per day
        "successful_trades" => Int(rand(2:5)),
        "win_rate" => rand(85:95)  # Yield farming usually stable
    )
end

function calculate_market_making_pnl_with_real_data(allocated_amount::Float64, settings::Dict, market_prices::Dict)
    total_spread_profit = 0.0
    total_volume = 0.0
    
    # Calculate spreads across all pairs
    for (pair, dex_prices) in market_prices
        if length(dex_prices) >= 2
            prices = [data["price"] for data in values(dex_prices)]
            volumes = [data["volume"] for data in values(dex_prices)]
            
            spread_pct = (maximum(prices) - minimum(prices)) / minimum(prices) * 100
            pair_volume = sum(volumes)
            
            # Market making profit from providing liquidity
            capital_efficiency = min(allocated_amount / 10000, 3.0)  # Max 3x leverage
            daily_volume_share = pair_volume * 0.01  # Assume 1% market share
            
            spread_profit = daily_volume_share * (spread_pct / 100) * 0.5 * capital_efficiency / 100
            total_spread_profit += spread_profit
            total_volume += daily_volume_share
        end
    end
    
    return Dict(
        "pnl_amount" => total_spread_profit,
        "total_trades" => Int(rand(15:40)),  # High frequency
        "successful_trades" => Int(rand(12:38)),
        "win_rate" => rand(80:95)
    )
end

# Strategy performance simulation logic
function simulate_strategy_pnl(strategy_type::String, allocated_amount::Float64, settings::Dict{String, Any})
    # Realistic simulation based on strategy type
    if strategy_type == "arbitrage"
        # Arbitrage typically has smaller but consistent gains
        daily_return_range = (-0.5, 3.0)  # -0.5% to 3% daily
        win_rate_range = (70, 90)
        trades_per_day_range = (5, 25)
    elseif strategy_type == "yield_farming"
        # Yield farming has moderate consistent returns
        daily_return_range = (-1.0, 2.5)  # -1% to 2.5% daily
        win_rate_range = (75, 95)
        trades_per_day_range = (2, 8)
    elseif strategy_type == "market_making"
        # Market making has smaller but very consistent returns
        daily_return_range = (-0.3, 1.8)  # -0.3% to 1.8% daily
        win_rate_range = (80, 98)
        trades_per_day_range = (10, 50)
    else
        # Default conservative simulation
        daily_return_range = (-0.8, 2.0)
        win_rate_range = (60, 85)
        trades_per_day_range = (3, 15)
    end
    
    # Generate random but realistic values
    daily_return_pct = daily_return_range[1] + rand() * (daily_return_range[2] - daily_return_range[1])
    win_rate = win_rate_range[1] + rand() * (win_rate_range[2] - win_rate_range[1])
    total_trades = Int(trades_per_day_range[1] + rand() * (trades_per_day_range[2] - trades_per_day_range[1]))
    
    pnl_amount = allocated_amount * (daily_return_pct / 100)
    successful_trades = Int(ceil(total_trades * (win_rate / 100)))
    
    return Dict(
        "pnl_amount" => pnl_amount,
        "total_trades" => total_trades,
        "successful_trades" => successful_trades,
        "win_rate" => win_rate
    )
end

end # module AlgoFiAPI