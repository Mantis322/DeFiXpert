"""
Swarm API Module
Real-time AI Swarm Intelligence Management for Trading Optimization
"""

using HTTP, JSON3, Dates, Random
using LibPQ  # PostgreSQL connectivity
using DotEnv

# Load environment variables
DotEnv.config()

# Include swarm algorithms
include("../strategies/TradingStrategyFramework.jl")

# Database connection helper
function get_swarm_connection()
    try
        db_host = get(ENV, "DB_HOST", "localhost")
        db_port = get(ENV, "DB_PORT", "5432")
        db_name = get(ENV, "DB_NAME", "algofi_db")
        db_user = get(ENV, "DB_USER", "postgres")
        db_password = get(ENV, "DB_PASSWORD", "postgres")
        
        conn_str = "host=$db_host port=$db_port dbname=$db_name user=$db_user password=$db_password"
        return LibPQ.Connection(conn_str)
    catch e
        @error "Failed to connect to swarm database" error=e
        return nothing
    end
end

"""
Swarm Agent Structure
"""
mutable struct SwarmAgent
    id::Int
    agent_name::String
    strategy_type::String
    profit::Float64
    success_rate::Float64
    status::String
    fitness::Float64
    position_x::Float64
    position_y::Float64
    config_data::Dict{String, Any}
    last_update::DateTime
    
    function SwarmAgent(name::String, strategy::String)
        new(0, name, strategy, 0.0, 0.0, "active", rand(), 
            rand() * 100, rand() * 100, Dict(), now())
    end
end

"""
Swarm Configuration Structure
"""
mutable struct SwarmConfig
    config_name::String
    population_size::Int
    inertia_weight::Float64
    cognitive_coeff::Float64
    social_coeff::Float64
    max_iterations::Int
    convergence_threshold::Float64
    risk_tolerance::Float64
    auto_optimize::Bool
    
    function SwarmConfig()
        new("default", 20, 0.5, 1.5, 1.5, 100, 0.001, 0.3, true)
    end
end

"""
GET /api/swarm/status - Get current swarm status
"""
function get_swarm_status(req::HTTP.Request)
    try
        conn = get_swarm_connection()
        if conn === nothing
            return HTTP.Response(500, [], JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Get active agents count
        result = execute(conn, "SELECT COUNT(*) as total, status, COUNT(*) as count FROM swarm_agents GROUP BY status")
        status_counts = Dict()
        total_agents = 0
        
        for row in result
            status = row.status
            count = row.count
            status_counts[status] = count
            total_agents += count
        end
        
        # Get current swarm configuration
        config_result = execute(conn, "SELECT * FROM swarm_configs WHERE config_name = 'default' LIMIT 1")
        config = nothing
        for row in config_result
            config = Dict(
                "population_size" => row.population_size,
                "inertia_weight" => row.inertia_weight,
                "cognitive_coeff" => row.cognitive_coeff,
                "social_coeff" => row.social_coeff,
                "max_iterations" => row.max_iterations,
                "convergence_threshold" => row.convergence_threshold,
                "risk_tolerance" => row.risk_tolerance,
                "auto_optimize" => row.auto_optimize
            )
            break
        end
        
        close(conn)
        
        response_data = Dict(
            "status" => total_agents > 0 ? "running" : "stopped",
            "total_agents" => total_agents,
            "agent_status" => status_counts,
            "config" => config,
            "timestamp" => now()
        )
        
        return HTTP.Response(200, 
            ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], 
            JSON3.write(response_data))
        
    catch e
        @error "Error getting swarm status" error=e
        return HTTP.Response(500, [], JSON3.write(Dict("error" => "Internal server error")))
    end
end

"""
GET /api/swarm/agents - Get all swarm agents with their current state
"""
function get_swarm_agents(req::HTTP.Request)
    try
        conn = get_swarm_connection()
        if conn === nothing
            return HTTP.Response(500, [], JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Get all agents with latest metrics
        query = """
        SELECT 
            sa.id, sa.agent_name, sa.strategy_type, sa.profit, sa.success_rate,
            sa.status, sa.fitness, sa.position_x, sa.position_y, sa.config_data,
            sa.last_update, sa.created_at
        FROM swarm_agents sa
        ORDER BY sa.last_update DESC
        """
        
        result = execute(conn, query)
        agents = []
        
        for row in result
            agent = Dict(
                "id" => row.id,
                "name" => row.agent_name,
                "strategy" => row.strategy_type,
                "profit" => row.profit,
                "successRate" => row.success_rate,
                "status" => row.status,
                "fitness" => row.fitness,
                "position" => Dict("x" => row.position_x, "y" => row.position_y),
                "lastUpdate" => row.last_update,
                "configData" => row.config_data !== nothing ? JSON3.read(string(row.config_data)) : Dict()
            )
            push!(agents, agent)
        end
        
        close(conn)
        
        return HTTP.Response(200, 
            ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], 
            JSON3.write(agents))
            
    catch e
        @error "Error getting swarm agents" error=e
        return HTTP.Response(500, [], JSON3.write(Dict("error" => "Internal server error")))
    end
end

"""
POST /api/swarm/start - Start the swarm with given configuration
"""
function start_swarm(req::HTTP.Request)
    try
        # Parse request body
        body_data = JSON3.read(String(req.body))
        
        conn = get_swarm_connection()
        if conn === nothing
            return HTTP.Response(500, [], JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Update or insert swarm configuration
        config_query = """
        INSERT INTO swarm_configs (config_name, population_size, inertia_weight, cognitive_coeff, 
                                 social_coeff, max_iterations, convergence_threshold, risk_tolerance, auto_optimize)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)
        ON CONFLICT (config_name) 
        DO UPDATE SET 
            population_size = \$2, inertia_weight = \$3, cognitive_coeff = \$4,
            social_coeff = \$5, max_iterations = \$6, convergence_threshold = \$7,
            risk_tolerance = \$8, auto_optimize = \$9, updated_at = NOW()
        """
        
        population_size = get(body_data, "populationSize", 20)
        inertia_weight = get(body_data, "inertiaWeight", 0.5)
        cognitive_coeff = get(body_data, "cognitiveCoeff", 1.5)
        social_coeff = get(body_data, "socialCoeff", 1.5)
        max_iterations = get(body_data, "maxIterations", 100)
        convergence_threshold = get(body_data, "convergenceThreshold", 0.001)
        risk_tolerance = get(body_data, "riskTolerance", 0.3)
        auto_optimize = get(body_data, "autoOptimize", true)
        
        execute(conn, config_query, [
            "default", population_size, inertia_weight, cognitive_coeff, social_coeff,
            max_iterations, convergence_threshold, risk_tolerance, auto_optimize
        ])
        
        # Generate initial swarm agents if they don't exist
        check_agents = execute(conn, "SELECT COUNT(*) as count FROM swarm_agents")
        agent_count = 0
        for row in check_agents
            agent_count = row.count
            break
        end
        
        if agent_count < population_size
            strategies = ["Yield Farming", "Arbitrage", "Liquidity Providing", "Portfolio Rebalancing"]
            
            for i in 1:population_size
                strategy = strategies[((i-1) % length(strategies)) + 1]
                agent_name = "Agent-$i"
                
                insert_query = """
                INSERT INTO swarm_agents (agent_name, strategy_type, profit, success_rate, 
                                        status, fitness, position_x, position_y, config_data)
                VALUES (\$1, \$2, \$3, \$4, 'active', \$5, \$6, \$7, \$8)
                ON CONFLICT (agent_name) 
                DO UPDATE SET status = 'active', last_update = NOW()
                """
                
                config_data = JSON3.write(Dict(
                    "learning_rate" => rand() * 0.1 + 0.01,
                    "risk_factor" => rand() * 0.5 + 0.1,
                    "optimization_target" => strategy
                ))
                
                execute(conn, insert_query, [
                    agent_name, strategy, rand() * 2.0 - 1.0, rand() * 100,
                    rand(), rand() * 100, rand() * 100, config_data
                ])
            end
        end
        
        close(conn)
        
        return HTTP.Response(200, 
            ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], 
            JSON3.write(Dict("status" => "started", "message" => "Swarm started successfully")))
            
    catch e
        @error "Error starting swarm" error=e
        return HTTP.Response(500, [], JSON3.write(Dict("error" => "Internal server error")))
    end
end

"""
POST /api/swarm/stop - Stop the swarm
"""
function stop_swarm(req::HTTP.Request)
    try
        conn = get_swarm_connection()
        if conn === nothing
            return HTTP.Response(500, [], JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Update all agents to stopped status
        execute(conn, "UPDATE swarm_agents SET status = 'stopped', last_update = NOW()")
        
        close(conn)
        
        return HTTP.Response(200, 
            ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], 
            JSON3.write(Dict("status" => "stopped", "message" => "Swarm stopped successfully")))
            
    catch e
        @error "Error stopping swarm" error=e
        return HTTP.Response(500, [], JSON3.write(Dict("error" => "Internal server error")))
    end
end

"""
GET /api/swarm/metrics - Get detailed swarm performance metrics
"""
function get_swarm_metrics(req::HTTP.Request)
    try
        conn = get_swarm_connection()
        if conn === nothing
            return HTTP.Response(500, [], JSON3.write(Dict("error" => "Database connection failed")))
        end
        
        # Get aggregated metrics
        metrics_query = """
        SELECT 
            AVG(profit) as avg_profit,
            MAX(profit) as max_profit,
            MIN(profit) as min_profit,
            AVG(success_rate) as avg_success_rate,
            AVG(fitness) as avg_fitness,
            COUNT(*) as total_agents
        FROM swarm_agents 
        WHERE status != 'stopped'
        """
        
        result = execute(conn, metrics_query)
        metrics = Dict()
        
        for row in result
            metrics = Dict(
                "averageProfit" => row.avg_profit !== nothing ? row.avg_profit : 0.0,
                "maxProfit" => row.max_profit !== nothing ? row.max_profit : 0.0,
                "minProfit" => row.min_profit !== nothing ? row.min_profit : 0.0,
                "averageSuccessRate" => row.avg_success_rate !== nothing ? row.avg_success_rate : 0.0,
                "averageFitness" => row.avg_fitness !== nothing ? row.avg_fitness : 0.0,
                "totalAgents" => row.total_agents !== nothing ? row.total_agents : 0
            )
            break
        end
        
        # Get strategy distribution
        strategy_query = """
        SELECT strategy_type, COUNT(*) as count, AVG(profit) as avg_profit
        FROM swarm_agents 
        GROUP BY strategy_type
        """
        
        strategy_result = execute(conn, strategy_query)
        strategies = []
        
        for row in strategy_result
            push!(strategies, Dict(
                "strategy" => row.strategy_type,
                "count" => row.count,
                "averageProfit" => row.avg_profit !== nothing ? row.avg_profit : 0.0
            ))
        end
        
        close(conn)
        
        response_data = merge(metrics, Dict("strategies" => strategies, "timestamp" => now()))
        
        return HTTP.Response(200, 
            ["Content-Type" => "application/json", "Access-Control-Allow-Origin" => "*"], 
            JSON3.write(response_data))
            
    catch e
        @error "Error getting swarm metrics" error=e
        return HTTP.Response(500, [], JSON3.write(Dict("error" => "Internal server error")))
    end
end

"""
Background swarm optimization task
"""
function optimize_swarm_agents()
    @info "Starting swarm optimization background task..."
    
    while true
        try
            conn = get_swarm_connection()
            if conn !== nothing
                # Get active agents
                active_agents = execute(conn, "SELECT * FROM swarm_agents WHERE status = 'active'")
                
                for row in active_agents
                    # Simulate swarm intelligence optimization
                    new_profit = row.profit + (rand() - 0.5) * 0.1
                    new_success_rate = max(0, min(100, row.success_rate + (rand() - 0.5) * 5))
                    new_fitness = rand()
                    new_pos_x = max(0, min(100, row.position_x + (rand() - 0.5) * 5))
                    new_pos_y = max(0, min(100, row.position_y + (rand() - 0.5) * 5))
                    
                    # Update agent with new values
                    update_query = """
                    UPDATE swarm_agents 
                    SET profit = \$1, success_rate = \$2, fitness = \$3, 
                        position_x = \$4, position_y = \$5, last_update = NOW()
                    WHERE id = \$6
                    """
                    
                    execute(conn, update_query, [
                        new_profit, new_success_rate, new_fitness,
                        new_pos_x, new_pos_y, row.id
                    ])
                    
                    # Record metric history
                    execute(conn, 
                        "INSERT INTO swarm_metrics (agent_id, metric_type, metric_value) VALUES (\$1, 'profit', \$2)",
                        [row.id, new_profit])
                end
                
                close(conn)
            end
            
            sleep(3) # Update every 3 seconds
            
        catch e
            @error "Error in swarm optimization" error=e
            sleep(5) # Wait longer on error
        end
    end
end

# Export API functions
export get_swarm_status, get_swarm_agents, start_swarm, stop_swarm, get_swarm_metrics, optimize_swarm_agents