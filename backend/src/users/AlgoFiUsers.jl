module AlgoFiUsers

using LibPQ
using JSON3
using Dates
using TimeZones

# Include database configuration
include("../db/DBConfig.jl")
using .DBConfig

export User, UserPerformance, UserStrategy, TradingTransaction
export create_user, get_user, update_user, delete_user
export get_user_performance, update_user_performance
export get_user_strategies, create_user_strategy, update_user_strategy
export log_trading_transaction, get_user_transactions
export get_portfolio_snapshot, create_portfolio_snapshot

# Data structures
struct User
    wallet_address::String
    created_at::Union{DateTime, ZonedDateTime}
    last_login::Union{DateTime, ZonedDateTime, Nothing}
    settings::Dict{String, Any}
    is_active::Bool
end

struct UserPerformance
    wallet_address::String
    date::Date
    total_invested_algo::Float64
    current_value_algo::Float64
    total_pnl_algo::Float64
    win_rate::Float64
    total_trades::Int
    successful_trades::Int
end

struct UserStrategy
    id::Int
    wallet_address::String
    strategy_name::String
    strategy_type::String
    settings::Dict{String, Any}
    allocated_amount::Float64
    is_active::Bool
    performance_score::Union{Float64, Nothing}
    current_pnl::Union{Float64, Nothing}
    created_at::Union{DateTime, ZonedDateTime}
end

struct TradingTransaction
    id::Int
    wallet_address::String
    strategy_id::Union{Int, Nothing}
    transaction_type::String
    asset_id::Union{String, Nothing}
    amount::Union{Float64, Nothing}
    price::Union{Float64, Nothing}
    pnl_amount::Union{Float64, Nothing}
    transaction_hash::Union{String, Nothing}
    timestamp::Union{DateTime, ZonedDateTime}
    metadata::Dict{String, Any}
end

# Database connection function
"""
Get PostgreSQL database connection using LibPQ
"""
function get_connection()
    return LibPQ.Connection(DBConfig.get_db_connection_string())
end

# User management functions
function create_user(wallet_address::String, account_info::Dict{String, Any})::User
    conn = get_connection()
    
    # Merge provided account_info under settings.account_info
    settings = Dict{String, Any}(
        "riskLevel" => "medium",
        "maxInvestment" => 1000,
        "autoTrading" => false,
        "notifications" => true,
        "account_info" => account_info
    )
    
    query = """
        INSERT INTO users (wallet_address, settings, last_login)
        VALUES (\$1, \$2, NOW())
        ON CONFLICT (wallet_address)
        DO UPDATE SET 
            settings = EXCLUDED.settings,
            last_login = NOW()
        RETURNING wallet_address, created_at, last_login, settings, is_active
    """
    
    result = execute(conn, query, [wallet_address, JSON3.write(settings)])
    
    row = first(result)
    
    return User(
        row[1],                 # wallet_address
        row[2],                 # created_at
        row[3],                 # last_login
        JSON3.read(row[4], Dict{String, Any}), # settings
        row[5]                  # is_active
    )
end

function get_user(wallet_address::String)::Union{User, Nothing}
    conn = get_connection()
    
    query = """
        SELECT wallet_address, created_at, last_login, settings, is_active
        FROM users 
        WHERE wallet_address = \$1 AND is_active = true
    """
    
    result = execute(conn, query, [wallet_address])
    
    if isempty(result)
        return nothing
    end
    
    row = first(result)
    
    return User(
        row[1],                 # wallet_address
        row[2],                 # created_at
        row[3],                 # last_login
        JSON3.read(row[4], Dict{String, Any}), # settings
        row[5]                  # is_active
    )
end

function update_user_account_info(wallet_address::String, account_info::Dict{String, Any})
    conn = get_connection()
    
    # Put account_info under settings.account_info JSON key
    # We build a small JSON object {"account_info": <account_info>} and merge with existing settings
    patch_json = Dict("account_info" => account_info)
    query = """
        UPDATE users 
        SET settings = COALESCE(settings, '{}') || (\$2)
        WHERE wallet_address = \$1
    """
    execute(conn, query, [wallet_address, JSON3.write(patch_json)])
end

function get_user_performance(wallet_address::String, days::Int = 30)::Vector{UserPerformance}
    conn = get_connection()
    
    query = """
            SELECT wallet_address, date, total_invested_algo, current_value_algo, total_pnl_algo,
                   win_rate, total_trades, successful_trades
            FROM user_performance
            WHERE wallet_address = \$1 
                AND date >= CURRENT_DATE - \$2 * INTERVAL '1 day'
            ORDER BY date DESC
    """

    result = execute(conn, query, [wallet_address, days])

    return [UserPerformance(row...) for row in result]
end

function update_user_performance(wallet_address::String, date::Date,
                                total_invested_algo::Float64, current_value_algo::Float64,
                                total_pnl_algo::Float64, win_rate::Float64,
                                total_trades::Int, successful_trades::Int)
    conn = get_connection()
    
    query = """
        INSERT INTO user_performance 
            (wallet_address, date, total_invested_algo, current_value_algo, total_pnl_algo,
             win_rate, total_trades, successful_trades)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8)
        ON CONFLICT (wallet_address, date)
        DO UPDATE SET 
            total_invested_algo = EXCLUDED.total_invested_algo,
            current_value_algo = EXCLUDED.current_value_algo,
            total_pnl_algo = EXCLUDED.total_pnl_algo,
            win_rate = EXCLUDED.win_rate,
            total_trades = EXCLUDED.total_trades,
            successful_trades = EXCLUDED.successful_trades
    """
    
    execute(conn, query, [wallet_address, date, total_invested_algo, current_value_algo,
                         total_pnl_algo, win_rate, total_trades, successful_trades])
end

function get_user_strategies(wallet_address::String)::Vector{UserStrategy}
    conn = get_connection()
    
    query = """
        SELECT id, wallet_address, strategy_name, strategy_type, settings,
               allocated_amount, is_active, performance_score, current_pnl, created_at
        FROM user_strategies
        WHERE wallet_address = \$1
        ORDER BY created_at DESC
    """
    
    result = execute(conn, query, [wallet_address])
    
    return [UserStrategy(
        row[1], row[2], row[3], row[4],
        JSON3.read(row[5], Dict{String, Any}),
        row[6], row[7], row[8], row[9], row[10]
    ) for row in result]
end

function create_user_strategy(wallet_address::String, strategy_name::String,
                             strategy_type::String, settings::Dict{String, Any},
                             allocated_amount::Float64)::UserStrategy
    conn = get_connection()
    
    query = """
        INSERT INTO user_strategies 
            (wallet_address, strategy_name, strategy_type, settings, allocated_amount, is_active)
        VALUES (\$1, \$2, \$3, \$4, \$5, true)
        RETURNING id, wallet_address, strategy_name, strategy_type, settings,
                  allocated_amount, is_active, performance_score, current_pnl, created_at
    """
    
    result = execute(conn, query, [
        wallet_address, strategy_name, strategy_type, 
        JSON3.write(settings), allocated_amount
    ])
    
    row = first(result)
    
    return UserStrategy(
        row[1], row[2], row[3], row[4],
        JSON3.read(row[5], Dict{String, Any}),
        row[6], row[7], row[8], row[9], row[10]
    )
end

function update_user_strategy(wallet_address::String, id::Int;
                              strategy_name::Union{String, Nothing}=nothing,
                              strategy_type::Union{String, Nothing}=nothing,
                              settings::Union{Dict{String, Any}, Nothing}=nothing,
                              allocated_amount::Union{Float64, Nothing}=nothing,
                              is_active::Union{Bool, Nothing}=nothing)::UserStrategy
    conn = get_connection()

    query = """
        UPDATE user_strategies
        SET
            strategy_name = COALESCE(\$3, strategy_name),
            strategy_type = COALESCE(\$4, strategy_type),
            settings      = COALESCE(\$5, settings),
            allocated_amount = COALESCE(\$6, allocated_amount),
            is_active     = COALESCE(\$7, is_active)
        WHERE wallet_address = \$1 AND id = \$2
        RETURNING id, wallet_address, strategy_name, strategy_type, settings,
                  allocated_amount, is_active, performance_score, current_pnl, created_at
    """

    params_json = settings === nothing ? nothing : JSON3.write(settings)
    result = execute(conn, query, [
        wallet_address, id, strategy_name, strategy_type, params_json, allocated_amount, is_active
    ])

    if isempty(result)
        error("Strategy not found or not owned by wallet")
    end

    row = first(result)
    return UserStrategy(
        row[1], row[2], row[3], row[4],
        JSON3.read(row[5], Dict{String, Any}),
        row[6], row[7], row[8], row[9], row[10]
    )
end

function log_trading_transaction(wallet_address::String,
                                strategy_id::Union{Int, Nothing}, transaction_type::String,
                                asset_id::Union{String, Nothing}, amount::Union{Float64, Nothing},
                                price::Union{Float64, Nothing}, pnl_amount::Union{Float64, Nothing} = nothing,
                                transaction_hash::Union{String, Nothing} = nothing,
                                metadata::Union{Dict{String, Any}, Nothing} = nothing)
    conn = get_connection()
    
    query = """
        INSERT INTO trading_transactions 
            (wallet_address, strategy_id, transaction_type, asset_id, amount, price, pnl_amount,
             transaction_hash, metadata)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
    """
    
    execute(conn, query, [
        wallet_address, strategy_id, transaction_type,
        asset_id, amount, price, pnl_amount, transaction_hash,
        metadata === nothing ? JSON3.write(Dict{String,Any}()) : JSON3.write(metadata)
    ])
end

function get_user_transactions(wallet_address::String, limit::Int = 100)::Vector{TradingTransaction}
    conn = get_connection()
    
    query = """
        SELECT id, wallet_address, strategy_id, transaction_type,
               asset_id, amount, price, pnl_amount, transaction_hash,
               timestamp, metadata
        FROM trading_transactions
        WHERE wallet_address = \$1
        ORDER BY timestamp DESC
        LIMIT \$2
    """
    
    result = execute(conn, query, [wallet_address, limit])
    
    return [TradingTransaction(
        row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10],
        JSON3.read(row[11], Dict{String, Any})
    ) for row in result]
end

function create_portfolio_snapshot(wallet_address::String, total_value_algo::Float64,
                                  asset_breakdown::Dict{String, Any},
                                  strategy_breakdown::Dict{String, Any})
    conn = get_connection()
    
    query = """
        INSERT INTO portfolio_snapshots 
            (wallet_address, total_value_algo, asset_breakdown, strategy_breakdown)
        VALUES (\$1, \$2, \$3, \$4)
    """
    
    execute(conn, query, [
        wallet_address, total_value_algo,
        JSON3.write(asset_breakdown), JSON3.write(strategy_breakdown)
    ])
end

function get_portfolio_snapshot(wallet_address::String)::Union{Dict{String, Any}, Nothing}
    conn = get_connection()
    
    query = """
        SELECT total_value_algo, asset_breakdown, strategy_breakdown, snapshot_date
        FROM portfolio_snapshots
        WHERE wallet_address = \$1
        ORDER BY snapshot_date DESC
        LIMIT 1
    """
    
    result = execute(conn, query, [wallet_address])
    
    if isempty(result)
        return nothing
    end
    
    row = first(result)
    
    return Dict{String, Any}(
        "total_value_algo" => row[1],
        "asset_breakdown" => JSON3.read(row[2], Dict{String, Any}),
        "strategy_breakdown" => JSON3.read(row[3], Dict{String, Any}),
        "snapshot_date" => row[4]
    )
end

end # module AlgoFiUsers
