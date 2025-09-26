module StrategyAPI

using HTTP, JSON3
using ..JuliaOSBackend.Database: get_connection
using ..JuliaOSBackend.Agents: CommonTypes
using LibPQ
using TimeZones, Dates

export handle_strategies_request

# Strategy endpoints handler
function handle_strategies_request(req::HTTP.Request)
    try
        # Parse path and method
        path_parts = split(req.target, "/")
        method = req.method
        
        if length(path_parts) >= 3 && path_parts[3] == "strategies"
            if method == "GET"
                return get_user_strategies(req)
            elseif method == "POST"
                return create_user_strategy(req)
            elseif method == "PUT" && length(path_parts) >= 4
                return update_user_strategy(req, path_parts[4])
            elseif method == "DELETE" && length(path_parts) >= 4
                return delete_user_strategy(req, path_parts[4])
            end
        end
        
        return HTTP.Response(404, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Strategy endpoint not found")))
    catch e
        @error "Strategy API error" exception=e
        return HTTP.Response(500, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Internal server error")))
    end
end

# Get all strategies for a user
function get_user_strategies(req::HTTP.Request)
    try
        # Extract user_id from headers or query params
        user_id = get_user_id_from_request(req)
        if user_id === nothing
            return HTTP.Response(401, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        conn = get_connection()
        
        # Query user strategies
        query = """
            SELECT 
                s.id,
                s.strategy_name,
                s.strategy_type,
                s.allocated_amount,
                s.is_active,
                s.settings,
                s.created_at,
                s.updated_at,
                COALESCE(
                    (SELECT SUM(pnl) FROM strategy_performance sp WHERE sp.strategy_id = s.id), 
                    0
                ) as current_pnl,
                COALESCE(
                    (SELECT AVG(performance_score) FROM strategy_performance sp 
                     WHERE sp.strategy_id = s.id AND sp.created_at >= NOW() - INTERVAL '30 days'), 
                    0.5
                ) as performance_score
            FROM strategies s
            WHERE s.user_id = \$1
            ORDER BY s.created_at DESC
        """
        
        result = execute(conn, query, [user_id])
        strategies = []
        
        for row in result
            push!(strategies, Dict(
                "id" => row[1],
                "strategy_name" => row[2],
                "strategy_type" => row[3],
                "allocated_amount" => parse(Float64, string(row[4])),
                "is_active" => row[5],
                "settings" => isnothing(row[6]) ? Dict() : JSON3.read(row[6]),
                "created_at" => string(row[7]),
                "updated_at" => string(row[8]),
                "current_pnl" => parse(Float64, string(row[9])),
                "performance_score" => parse(Float64, string(row[10]))
            ))
        end
        
        close(conn)
        
        return HTTP.Response(200, ["Content-Type" => "application/json"], 
                           JSON3.write(strategies))
    catch e
        @error "Get strategies error" exception=e
        return HTTP.Response(500, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Failed to get strategies")))
    end
end

# Create new strategy
function create_user_strategy(req::HTTP.Request)
    try
        user_id = get_user_id_from_request(req)
        if user_id === nothing
            return HTTP.Response(401, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        # Parse request body
        body = String(req.body)
        strategy_data = JSON3.read(body)
        
        # Validate required fields
        if !haskey(strategy_data, "strategy_name") || !haskey(strategy_data, "strategy_type")
            return HTTP.Response(400, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Missing required fields")))
        end
        
        # Validate strategy type
        valid_types = ["arbitrage", "yield_farming", "market_making"]
        if !(strategy_data["strategy_type"] in valid_types)
            return HTTP.Response(400, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Invalid strategy type")))
        end
        
        conn = get_connection()
        
        # Insert new strategy
        query = """
            INSERT INTO strategies (
                user_id, strategy_name, strategy_type, allocated_amount, 
                is_active, settings, created_at, updated_at
            ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, NOW(), NOW())
            RETURNING id
        """
        
        settings_json = haskey(strategy_data, "settings") ? 
                       JSON3.write(strategy_data["settings"]) : "{}"
        
        result = execute(conn, query, [
            user_id,
            strategy_data["strategy_name"],
            strategy_data["strategy_type"],
            get(strategy_data, "allocated_amount", 100.0),
            get(strategy_data, "is_active", false),
            settings_json
        ])
        
        strategy_id = first(result)[1]
        close(conn)
        
        # Initialize strategy in execution engine (if active)
        if get(strategy_data, "is_active", false)
            initialize_strategy_execution(strategy_id, strategy_data)
        end
        
        response_data = Dict(
            "id" => strategy_id,
            "message" => "Strategy created successfully"
        )
        
        return HTTP.Response(201, ["Content-Type" => "application/json"], 
                           JSON3.write(response_data))
    catch e
        @error "Create strategy error" exception=e
        return HTTP.Response(500, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Failed to create strategy")))
    end
end

# Update existing strategy
function update_user_strategy(req::HTTP.Request, strategy_id_str::String)
    try
        user_id = get_user_id_from_request(req)
        if user_id === nothing
            return HTTP.Response(401, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        strategy_id = parse(Int, strategy_id_str)
        body = String(req.body)
        update_data = JSON3.read(body)
        
        conn = get_connection()
        
        # Verify ownership
        ownership_query = "SELECT user_id FROM strategies WHERE id = \$1"
        ownership_result = execute(conn, ownership_query, [strategy_id])
        
        if isempty(ownership_result) || first(ownership_result)[1] != user_id
            close(conn)
            return HTTP.Response(403, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Strategy not found or access denied")))
        end
        
        # Build dynamic update query
        update_fields = []
        update_values = []
        param_count = 1
        
        for (field, value) in pairs(update_data)
            if field in ["strategy_name", "allocated_amount", "is_active"]
                push!(update_fields, "$field = \$$param_count")
                push!(update_values, value)
                param_count += 1
            elseif field == "settings"
                push!(update_fields, "settings = \$$param_count")
                push!(update_values, JSON3.write(value))
                param_count += 1
            end
        end
        
        if isempty(update_fields)
            close(conn)
            return HTTP.Response(400, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "No valid fields to update")))
        end
        
        # Add updated_at field
        push!(update_fields, "updated_at = NOW()")
        
        query = "UPDATE strategies SET $(join(update_fields, ", ")) WHERE id = \$$param_count"
        push!(update_values, strategy_id)
        
        execute(conn, query, update_values)
        close(conn)
        
        # Handle strategy activation/deactivation
        if haskey(update_data, "is_active")
            if update_data["is_active"]
                initialize_strategy_execution(strategy_id, update_data)
            else
                stop_strategy_execution(strategy_id)
            end
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("message" => "Strategy updated successfully")))
    catch e
        @error "Update strategy error" exception=e
        return HTTP.Response(500, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Failed to update strategy")))
    end
end

# Delete strategy
function delete_user_strategy(req::HTTP.Request, strategy_id_str::String)
    try
        user_id = get_user_id_from_request(req)
        if user_id === nothing
            return HTTP.Response(401, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Unauthorized")))
        end
        
        strategy_id = parse(Int, strategy_id_str)
        conn = get_connection()
        
        # Verify ownership and check if active
        check_query = "SELECT user_id, is_active FROM strategies WHERE id = \$1"
        check_result = execute(conn, check_query, [strategy_id])
        
        if isempty(check_result)
            close(conn)
            return HTTP.Response(404, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Strategy not found")))
        end
        
        row = first(check_result)
        if row[1] != user_id
            close(conn)
            return HTTP.Response(403, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Access denied")))
        end
        
        if row[2]  # is_active
            close(conn)
            return HTTP.Response(400, ["Content-Type" => "application/json"], 
                               JSON3.write(Dict("error" => "Cannot delete active strategy. Please deactivate first.")))
        end
        
        # Delete strategy (cascade will handle related records)
        delete_query = "DELETE FROM strategies WHERE id = \$1"
        execute(conn, delete_query, [strategy_id])
        close(conn)
        
        return HTTP.Response(200, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("message" => "Strategy deleted successfully")))
    catch e
        @error "Delete strategy error" exception=e
        return HTTP.Response(500, ["Content-Type" => "application/json"], 
                           JSON3.write(Dict("error" => "Failed to delete strategy")))
    end
end

# Helper function to extract user_id from request
function get_user_id_from_request(req::HTTP.Request)
    # Try to get from Authorization header
    if haskey(req.headers, "Authorization")
        auth_header = req.headers["Authorization"]
        if startswith(auth_header, "Bearer ")
            # Extract user_id from JWT token (simplified validation)
            token = replace(auth_header, "Bearer " => "")
            try
                # In production, properly validate JWT and extract user_id
                # For now, decode basic token format: "user_{user_id}"
                if startswith(token, "user_")
                    return replace(token, "user_" => "")
                end
                # Default user for development
                return "dev_user_001"
            catch e
                @warn "Failed to parse token" error=e
                return "anonymous_user"
            end
        end
    end
    
    # Try to get from query params
    uri_parts = split(req.target, "?")
    if length(uri_parts) > 1
        params = HTTP.queryparams(uri_parts[2])
        if haskey(params, "user_id")
            return params["user_id"]
        end
    end
    
    # Return default user for unauthenticated requests
    return "dev_user_001"
end

# Initialize strategy execution (placeholder)
function initialize_strategy_execution(strategy_id::Int, strategy_data::Dict)
    @info "Initializing strategy execution" strategy_id=strategy_id type=strategy_data["strategy_type"]
    # TODO: Integrate with StrategyExecutionEngine
    # This would register the strategy with the execution engine
    # and start monitoring for trading opportunities
end

# Stop strategy execution (placeholder)
function stop_strategy_execution(strategy_id::Int)
    @info "Stopping strategy execution" strategy_id=strategy_id
    # TODO: Integrate with StrategyExecutionEngine
    # This would remove the strategy from active execution
    # and stop any pending trades
end

end # module