"""
AlgorandClient.jl - Algorand blockchain client for JuliaOS

This module provides functionality for interacting with Algorand blockchain,
including ASA (Algorand Standard Assets) support, PyTeal smart contract interaction,
and native ALGO operations.
"""
module AlgorandClient

using HTTP, JSON3, Dates, Base64, Printf, Logging

export AlgorandConfig, AlgorandProvider, create_algorand_provider
export get_balance_algo, send_transaction_algo, get_account_info_algo
export get_asset_info_algo, get_application_info_algo, get_block_algo
export create_asset_transaction_algo, transfer_asset_algo, opt_in_asset_algo
export call_application_algo, create_application_algo
export algo_to_microalgo, microalgo_to_algo

"""
    AlgorandConfig

Configuration for an Algorand client connection.
"""
struct AlgorandConfig
    node_url::String
    node_token::String
    network::String  # "mainnet", "testnet", "betanet"
    indexer_url::String
    indexer_token::String
    default_fee::Int64  # In microAlgos
    timeout_seconds::Int
    
    function AlgorandConfig(;
        node_url::String,
        node_token::String = "",
        network::String = "testnet",
        indexer_url::String = "",
        indexer_token::String = "",
        default_fee::Int64 = 1000,  # 0.001 ALGO
        timeout_seconds::Int = 30
    )
        new(node_url, node_token, network, indexer_url, indexer_token, default_fee, timeout_seconds)
    end
end

"""
    AlgorandProvider

A provider for interacting with Algorand blockchain.
"""
mutable struct AlgorandProvider
    config::AlgorandConfig
    connected::Bool
    genesis_id::String
    genesis_hash::String
    last_round::Int64
    
    function AlgorandProvider(config::AlgorandConfig)
        new(config, false, "", "", 0)
    end
end

"""
    create_algorand_provider(config::AlgorandConfig) -> AlgorandProvider

Create and test connection to Algorand network.
"""
function create_algorand_provider(config::AlgorandConfig)::AlgorandProvider
    provider = AlgorandProvider(config)
    
    try
        # Test connection by getting network status
        status_response = _make_algorand_request(provider, "GET", "/v2/status")
        
        if haskey(status_response, "genesis-id") && haskey(status_response, "genesis-hash")
            provider.connected = true
            provider.genesis_id = status_response["genesis-id"]
            provider.genesis_hash = status_response["genesis-hash"] 
            provider.last_round = get(status_response, "last-round", 0)
            
            @info "Connected to Algorand $(config.network): genesis-id=$(provider.genesis_id)"
        else
            @error "Invalid response from Algorand node"
        end
        
    catch e
        @error "Failed to connect to Algorand node" error=e
        provider.connected = false
    end
    
    return provider
end

"""
    _make_algorand_request(provider::AlgorandProvider, method::String, endpoint::String, data=nothing)

Make HTTP request to Algorand node with proper authentication.
"""
function _make_algorand_request(provider::AlgorandProvider, method::String, endpoint::String, data=nothing)
    headers = Dict{String, String}()
    
    # Add authentication if token provided
    if !isempty(provider.config.node_token)
        headers["X-Algo-API-Token"] = provider.config.node_token
    end
    
    headers["Content-Type"] = "application/json"
    
    url = provider.config.node_url * endpoint
    
    try
        if method == "GET"
            response = HTTP.get(url, headers, readtimeout=provider.config.timeout_seconds)
        elseif method == "POST"
            body = data !== nothing ? JSON3.write(data) : ""
            response = HTTP.post(url, headers, body, readtimeout=provider.config.timeout_seconds)
        else
            error("Unsupported HTTP method: $method")
        end
        
        if response.status != 200
            error("HTTP $(response.status): $(String(response.body))")
        end
        
        return JSON3.read(response.body)
        
    catch e
        @error "Algorand API request failed" method=method endpoint=endpoint error=e
        rethrow(e)
    end
end

"""
    get_balance_algo(provider::AlgorandProvider, address::String) -> Float64

Get ALGO balance for an address in ALGO units.
"""
function get_balance_algo(provider::AlgorandProvider, address::String)::Float64
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        response = _make_algorand_request(provider, "GET", "/v2/accounts/$address")
        
        balance_microalgos = get(response, "amount", 0)
        return microalgo_to_algo(balance_microalgos)
        
    catch e
        @error "Failed to get ALGO balance for $address" error=e
        return 0.0
    end
end

"""
    get_account_info_algo(provider::AlgorandProvider, address::String) -> Dict

Get detailed account information including ASA holdings.
"""
function get_account_info_algo(provider::AlgorandProvider, address::String)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        return _make_algorand_request(provider, "GET", "/v2/accounts/$address")
    catch e
        @error "Failed to get account info for $address" error=e
        return Dict()
    end
end

"""
    get_asset_info_algo(provider::AlgorandProvider, asset_id::Int64) -> Dict

Get information about an Algorand Standard Asset (ASA).
"""
function get_asset_info_algo(provider::AlgorandProvider, asset_id::Int64)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        return _make_algorand_request(provider, "GET", "/v2/assets/$asset_id")
    catch e
        @error "Failed to get asset info for asset ID $asset_id" error=e
        return Dict()
    end
end

"""
    get_application_info_algo(provider::AlgorandProvider, app_id::Int64) -> Dict

Get information about an Algorand application (smart contract).
"""
function get_application_info_algo(provider::AlgorandProvider, app_id::Int64)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        return _make_algorand_request(provider, "GET", "/v2/applications/$app_id")
    catch e
        @error "Failed to get application info for app ID $app_id" error=e
        return Dict()
    end
end

"""
    get_block_algo(provider::AlgorandProvider, round::Int64) -> Dict

Get block information for a specific round.
"""
function get_block_algo(provider::AlgorandProvider, round::Int64)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        return _make_algorand_request(provider, "GET", "/v2/blocks/$round")
    catch e
        @error "Failed to get block for round $round" error=e
        return Dict()
    end
end

"""
    send_transaction_algo(provider::AlgorandProvider, signed_txn_bytes::Vector{UInt8}) -> String

Submit a signed transaction to the Algorand network.
Returns transaction ID if successful.
"""
function send_transaction_algo(provider::AlgorandProvider, signed_txn_bytes::Vector{UInt8})::String
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        # Algorand expects raw transaction bytes in POST body
        headers = Dict{String, String}()
        if !isempty(provider.config.node_token)
            headers["X-Algo-API-Token"] = provider.config.node_token
        end
        headers["Content-Type"] = "application/x-binary"
        
        url = provider.config.node_url * "/v2/transactions"
        
        response = HTTP.post(url, headers, signed_txn_bytes, readtimeout=provider.config.timeout_seconds)
        
        if response.status != 200
            error("Transaction submission failed: HTTP $(response.status)")
        end
        
        result = JSON3.read(response.body)
        return get(result, "txId", "")
        
    catch e
        @error "Failed to send transaction" error=e
        rethrow(e)
    end
end

"""
    create_payment_transaction_algo(provider::AlgorandProvider, from_addr::String, to_addr::String, amount_algo::Float64, note::String="") -> Dict

Create an unsigned payment transaction structure.
Note: This returns transaction parameters that need to be signed externally.
"""
function create_payment_transaction_algo(provider::AlgorandProvider, from_addr::String, to_addr::String, amount_algo::Float64, note::String="")::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    # Get current network parameters
    params_response = _make_algorand_request(provider, "GET", "/v2/transactions/params")
    
    # Convert amount to microAlgos
    amount_microalgos = algo_to_microalgo(amount_algo)
    
    transaction_params = Dict(
        "type" => "pay",
        "from" => from_addr,
        "to" => to_addr,
        "amount" => amount_microalgos,
        "fee" => provider.config.default_fee,
        "first-valid-round" => params_response["last-round"],
        "last-valid-round" => params_response["last-round"] + 1000,
        "genesis-id" => params_response["genesis-id"],
        "genesis-hash" => params_response["genesis-hash"]
    )
    
    if !isempty(note)
        transaction_params["note"] = base64encode(note)
    end
    
    return transaction_params
end

"""
    create_asset_transfer_transaction_algo(provider::AlgorandProvider, from_addr::String, to_addr::String, asset_id::Int64, amount::Int64, note::String="") -> Dict

Create an unsigned ASA transfer transaction.
"""
function create_asset_transfer_transaction_algo(provider::AlgorandProvider, from_addr::String, to_addr::String, asset_id::Int64, amount::Int64, note::String="")::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    params_response = _make_algorand_request(provider, "GET", "/v2/transactions/params")
    
    transaction_params = Dict(
        "type" => "axfer",
        "from" => from_addr,
        "to" => to_addr,
        "amount" => amount,
        "xaid" => asset_id,  # Asset ID
        "fee" => provider.config.default_fee,
        "first-valid-round" => params_response["last-round"],
        "last-valid-round" => params_response["last-round"] + 1000,
        "genesis-id" => params_response["genesis-id"],
        "genesis-hash" => params_response["genesis-hash"]
    )
    
    if !isempty(note)
        transaction_params["note"] = base64encode(note)
    end
    
    return transaction_params
end

"""
    create_asset_optin_transaction_algo(provider::AlgorandProvider, account_addr::String, asset_id::Int64) -> Dict

Create an asset opt-in transaction (required before receiving ASAs).
"""
function create_asset_optin_transaction_algo(provider::AlgorandProvider, account_addr::String, asset_id::Int64)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    params_response = _make_algorand_request(provider, "GET", "/v2/transactions/params")
    
    # Asset opt-in is an asset transfer to self with amount 0
    transaction_params = Dict(
        "type" => "axfer",
        "from" => account_addr,
        "to" => account_addr,  # To self
        "amount" => 0,         # Amount 0 for opt-in
        "xaid" => asset_id,
        "fee" => provider.config.default_fee,
        "first-valid-round" => params_response["last-round"],
        "last-valid-round" => params_response["last-round"] + 1000,
        "genesis-id" => params_response["genesis-id"],
        "genesis-hash" => params_response["genesis-hash"]
    )
    
    return transaction_params
end

"""
    call_application_algo(provider::AlgorandProvider, app_id::Int64, sender::String, app_args::Vector{String}=String[], accounts::Vector{String}=String[], foreign_apps::Vector{Int64}=Int64[], foreign_assets::Vector{Int64}=Int64[]) -> Dict

Create an application call transaction.
"""
function call_application_algo(provider::AlgorandProvider, app_id::Int64, sender::String; app_args::Vector{String}=String[], accounts::Vector{String}=String[], foreign_apps::Vector{Int64}=Int64[], foreign_assets::Vector{Int64}=Int64[])::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    params_response = _make_algorand_request(provider, "GET", "/v2/transactions/params")
    
    transaction_params = Dict(
        "type" => "appl",
        "from" => sender,
        "apid" => app_id,
        "fee" => provider.config.default_fee,
        "first-valid-round" => params_response["last-round"],
        "last-valid-round" => params_response["last-round"] + 1000,
        "genesis-id" => params_response["genesis-id"],
        "genesis-hash" => params_response["genesis-hash"]
    )
    
    if !isempty(app_args)
        # Convert string args to base64
        transaction_params["apaa"] = [base64encode(arg) for arg in app_args]
    end
    
    if !isempty(accounts)
        transaction_params["apat"] = accounts
    end
    
    if !isempty(foreign_apps)
        transaction_params["apfa"] = foreign_apps
    end
    
    if !isempty(foreign_assets)
        transaction_params["apas"] = foreign_assets
    end
    
    return transaction_params
end

# Utility functions for unit conversion

"""
    algo_to_microalgo(algo_amount::Float64) -> Int64

Convert ALGO to microAlgo (1 ALGO = 1,000,000 microAlgo).
"""
function algo_to_microalgo(algo_amount::Float64)::Int64
    return round(Int64, algo_amount * 1_000_000)
end

"""
    microalgo_to_algo(microalgo_amount::Int64) -> Float64

Convert microAlgo to ALGO.
"""
function microalgo_to_algo(microalgo_amount::Int64)::Float64
    return microalgo_amount / 1_000_000.0
end

"""
    get_suggested_params_algo(provider::AlgorandProvider) -> Dict

Get suggested transaction parameters from the network.
"""
function get_suggested_params_algo(provider::AlgorandProvider)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        return _make_algorand_request(provider, "GET", "/v2/transactions/params")
    catch e
        @error "Failed to get suggested transaction parameters" error=e
        return Dict()
    end
end

"""
    wait_for_confirmation_algo(provider::AlgorandProvider, txid::String, max_rounds::Int64=10) -> Dict

Wait for transaction confirmation and return transaction details.
"""
function wait_for_confirmation_algo(provider::AlgorandProvider, txid::String, max_rounds::Int64=10)::Dict
    if !provider.connected
        error("Not connected to Algorand network")
    end
    
    try
        # Get starting round
        status = _make_algorand_request(provider, "GET", "/v2/status")
        start_round = status["last-round"] + 1
        
        current_round = start_round
        while current_round < (start_round + max_rounds)
            try
                # Check if transaction is confirmed
                response = _make_algorand_request(provider, "GET", "/v2/transactions/$txid")
                
                if haskey(response, "confirmed-round") && response["confirmed-round"] > 0
                    @info "Transaction $txid confirmed in round $(response["confirmed-round"])"
                    return response
                end
            catch e
                # Transaction might not be found yet, continue waiting
            end
            
            # Wait for next round
            sleep(1)
            
            # Update current round
            status = _make_algorand_request(provider, "GET", "/v2/status")
            current_round = status["last-round"]
        end
        
        error("Transaction $txid not confirmed after $max_rounds rounds")
        
    catch e
        @error "Failed to wait for transaction confirmation" txid=txid error=e
        rethrow(e)
    end
end

end # module AlgorandClient