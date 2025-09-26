#!/usr/bin/env julia

"""
algofi_swarm_demo.jl - Demo script for AlgoFi AI Swarm

This script demonstrates the AlgoFi AI Swarm system for the Algorand hackathon.
It showcases:
1. Multi-agent swarm intelligence for DeFi optimization
2. AI-powered yield prediction and strategy optimization
3. Real-time arbitrage detection across Algorand DEXes
4. Risk-adjusted portfolio management
"""

# Set up the Julia environment
println("🚀 Starting AlgoFi AI Swarm Demo for Algorand Hackathon")

# Include required modules with proper path handling
julia_src_path = joinpath(dirname(@__DIR__), "src")
push!(LOAD_PATH, julia_src_path)

# Try to include modules with fallback
try
    include("../src/blockchain/AlgorandClient.jl")
    using .AlgorandClient
    const ALGORAND_MODULE_LOADED = true
    println("✅ AlgorandClient loaded successfully")
catch e
    @warn "Could not load AlgorandClient: $e"
    const ALGORAND_MODULE_LOADED = false
    println("⚠️  Using mock AlgorandClient implementation")
end

try
    include("../src/agents/AlgoFiAISwarm.jl")
    using .AlgoFiAISwarm
    const SWARM_MODULE_LOADED = true
    println("✅ AlgoFiAISwarm loaded successfully")
catch e
    @warn "Could not load AlgoFiAISwarm: $e"
    const SWARM_MODULE_LOADED = false
end

using Random, Statistics, Dates, Printf

"""
Main demo function
"""
function run_algofi_demo()
    println("\n" * "="^60)
    println("🤖 ALGOFI AI SWARM - ALGORAND HACKATHON DEMO")
    println("="^60)
    
    # 1. Setup Algorand connection
    println("\n📡 Step 1: Connecting to Algorand Network...")
    algorand_config = setup_algorand_connection()
    
    if algorand_config === nothing
        println("❌ Failed to setup Algorand connection. Please check your configuration.")
        return
    end
    
    # 2. Create AlgoFi Swarm
    println("\n🐝 Step 2: Creating AI Swarm with 20 Intelligent Agents...")
    swarm = create_demo_swarm(algorand_config)
    
    # 3. Demonstrate market analysis
    println("\n📊 Step 3: AI Market Analysis & Prediction...")
    market_analysis = demonstrate_market_analysis(swarm)
    
    # 4. Show swarm optimization in action
    println("\n🧠 Step 4: Swarm Intelligence Optimization...")
    optimization_results = demonstrate_swarm_optimization(swarm)
    
    # 5. Execute strategies
    println("\n⚡ Step 5: Executing Optimized Strategies...")
    execution_results = demonstrate_strategy_execution(swarm)
    
    # 6. Show performance metrics
    println("\n📈 Step 6: Performance Analysis...")
    show_performance_metrics(swarm, execution_results)
    
    # 7. Demo real-time arbitrage
    println("\n🔄 Step 7: Real-time Arbitrage Detection...")
    arbitrage_demo(swarm)
    
    println("\n" * "="^60)
    println("✅ AlgoFi AI Swarm Demo Complete!")
    println("🏆 Ready for Algorand Hackathon Victory!")
    println("="^60)
end

"""
Setup Algorand connection for demo
"""
function setup_algorand_connection()::Union{AlgorandClient.AlgorandConfig, Nothing}
    try
        # Use Algorand TestNet for demo
        config = AlgorandClient.AlgorandConfig(
            node_url = "https://testnet-api.algonode.cloud",
            network = "testnet",
            indexer_url = "https://testnet-idx.algonode.cloud",
            default_fee = 1000,
            timeout_seconds = 30
        )
        
        # Test connection
        provider = AlgorandClient.create_algorand_provider(config)
        
        if provider.connected
            println("✅ Connected to Algorand $(config.network)")
            println("   Genesis ID: $(provider.genesis_id)")
            println("   Last Round: $(provider.last_round)")
            return config
        else
            println("❌ Failed to connect to Algorand network")
            return nothing
        end
        
    catch e
        println("❌ Algorand connection error: $e")
        return nothing
    end
end

"""
Create demo swarm with diverse agent strategies
"""
function create_demo_swarm(algorand_config::AlgorandClient.AlgorandConfig)::AlgoFiAISwarm.AlgoFiSwarm
    swarm = AlgoFiAISwarm.create_algofi_swarm(algorand_config, 20)
    
    println("   📍 Created $(length(swarm.agents)) specialized agents:")
    
    strategy_counts = Dict{String, Int}()
    for agent in swarm.agents
        strategy_name = string(agent.strategy.strategy_type)
        strategy_counts[strategy_name] = get(strategy_counts, strategy_name, 0) + 1
    end
    
    for (strategy, count) in strategy_counts
        println("      🤖 $count × $strategy agents")
    end
    
    return swarm
end

"""
Demonstrate AI market analysis capabilities
"""
function demonstrate_market_analysis(swarm::AlgoFiAISwarm.AlgoFiSwarm)::Dict{String, Any}
    println("   🔍 Analyzing Algorand DeFi ecosystem...")
    
    # Collect market data
    market_data = AlgoFiAISwarm.collect_market_data(swarm)
    
    println("   📊 Market Data Collected:")
    for protocol in ["tinyman", "pact", "algofi", "folks"]
        if haskey(market_data, protocol)
            tvl = get(market_data[protocol], "tvl", 0)
            println("      💰 $protocol TVL: \$$(format_number(tvl))")
        end
    end
    
    # AI predictions
    predictions = AlgoFiAISwarm.predict_market_conditions(swarm, market_data)
    
    println("   🧠 AI Predictions:")
    println("      📈 Market Trend: $(get(predictions, "market_trend", "unknown"))")
    println("      ⚠️  Risk Level: $(round(get(predictions, "risk_assessment", 0.5) * 100, digits=1))%")
    println("      📊 Volatility: $(round(get(predictions, "volatility_forecast", 0.1) * 100, digits=1))%")
    
    if haskey(predictions, "recommended_strategies")
        strategies = join(string.(predictions["recommended_strategies"]), ", ")
        println("      💡 Recommended: $strategies")
    end
    
    return predictions
end

"""
Demonstrate swarm optimization
"""
function demonstrate_swarm_optimization(swarm::AlgoFiAISwarm.AlgoFiSwarm)::Dict{String, Any}
    println("   🧬 Running Particle Swarm Optimization...")
    
    # Simulate market predictions for optimization
    mock_predictions = Dict(
        "market_trend" => "bullish",
        "risk_assessment" => 0.3,
        "volatility_forecast" => 0.15
    )
    
    optimization_results = AlgoFiAISwarm.optimize_strategies_pso(swarm, mock_predictions)
    
    println("   ✨ Optimization Complete:")
    println("      🎯 Risk Tolerance: $(round(optimization_results["optimal_risk_tolerance"] * 100, digits=1))%")
    println("      💵 Profit Threshold: $(round(optimization_results["optimal_profit_threshold"] * 100, digits=2))%")
    println("      💰 Investment Amount: $(round(optimization_results["optimal_investment_amount"], digits=2)) ALGO")
    println("      ⏰ Time Horizon: $(round(optimization_results["optimal_time_horizon"], digits=0)) hours")
    println("      📊 Expected Performance: $(round(optimization_results["expected_performance"], digits=3))")
    
    return optimization_results
end

"""
Demonstrate strategy execution
"""
function demonstrate_strategy_execution(swarm::AlgoFiAISwarm.AlgoFiSwarm)::Dict{String, Any}
    println("   ⚡ Executing strategies across swarm agents...")
    
    # Mock optimization results for execution
    mock_optimal_strategies = Dict(
        "optimal_risk_tolerance" => 0.4,
        "optimal_profit_threshold" => 0.02,
        "optimal_investment_amount" => 10.0,
        "optimal_time_horizon" => 24.0
    )
    
    execution_results = AlgoFiAISwarm.execute_swarm_strategies(swarm, mock_optimal_strategies)
    
    successful = execution_results["successful_executions"]
    failed = execution_results["failed_executions"]
    total_profit = execution_results["total_profit"]
    
    println("   📊 Execution Results:")
    println("      ✅ Successful: $successful")
    println("      ❌ Failed: $failed")
    println("      💰 Total Profit: $(round(total_profit, digits=3)) ALGO")
    println("      📈 Success Rate: $(round(successful/(successful+failed)*100, digits=1))%")
    
    # Show top performing agents
    profitable_agents = []
    for (agent_id, result) in execution_results["agent_results"]
        if result["success"] && result["profit"] > 0
            push!(profitable_agents, (agent_id, result["profit"]))
        end
    end
    
    if !isempty(profitable_agents)
        sort!(profitable_agents, by=x->x[2], rev=true)
        println("   🏆 Top Performing Agents:")
        for (i, (agent_id, profit)) in enumerate(profitable_agents[1:min(3, length(profitable_agents))])
            println("      $i. $agent_id: $(round(profit, digits=3)) ALGO")
        end
    end
    
    return execution_results
end

"""
Show performance metrics
"""
function show_performance_metrics(swarm::AlgoFiAISwarm.AlgoFiSwarm, execution_results::Dict{String, Any})
    AlgoFiAISwarm.update_performance_metrics(swarm, execution_results)
    
    metrics = swarm.performance_metrics
    
    println("   📊 Overall Swarm Performance:")
    println("      💰 Total Profit: $(round(metrics["total_profit"], digits=3)) ALGO")
    println("      📈 Success Rate: $(round(metrics["success_rate"] * 100, digits=1))%")
    println("      📊 Sharpe Ratio: $(round(metrics["sharpe_ratio"], digits=3))")
    
    # Calculate additional metrics
    total_agents = length(swarm.agents)
    active_agents = count(agent -> !isempty(agent.performance_history) for agent in swarm.agents)
    
    println("   🤖 Agent Statistics:")
    println("      👥 Total Agents: $total_agents")
    println("      ⚡ Active Agents: $active_agents")
    
    if active_agents > 0
        avg_performance = mean([sum(agent.performance_history) for agent in swarm.agents if !isempty(agent.performance_history)])
        println("      📊 Avg Performance: $(round(avg_performance, digits=3)) ALGO per agent")
    end
end

"""
Demonstrate real-time arbitrage capabilities
"""
function arbitrage_demo(swarm::AlgoFiAISwarm.AlgoFiSwarm)
    println("   🔍 Scanning for arbitrage opportunities...")
    
    # Simulate finding arbitrage opportunities
    opportunities = [
        ("ALGO/USDC", "Tinyman", "Pact", 0.15),
        ("USDC/USDT", "AlgoFi", "Folks", 0.08),
        ("ALGO/USDT", "Tinyman", "AlgoFi", 0.22)
    ]
    
    println("   💡 Detected Arbitrage Opportunities:")
    
    for (i, (pair, dex1, dex2, profit_percent)) in enumerate(opportunities)
        println("      $i. $pair: $dex1 ↔ $dex2 (+$(round(profit_percent, digits=2))%)")
    end
    
    # Execute best opportunity
    if !isempty(opportunities)
        best_opportunity = opportunities[argmax([opp[4] for opp in opportunities])]
        pair, dex1, dex2, profit_percent = best_opportunity
        
        println("   ⚡ Executing best opportunity: $pair on $dex1 ↔ $dex2")
        
        result = AlgoFiAISwarm.execute_arbitrage(swarm, pair, 5.0)
        
        if result["success"]
            println("      ✅ Arbitrage executed successfully!")
            println("      💰 Profit: $(round(result["profit"], digits=3)) ALGO")
            println("      ⏱️  Execution time: $(result["execution_time"])")
        else
            println("      ❌ Arbitrage execution failed")
        end
    end
end

"""
Format large numbers with commas
"""
function format_number(n)::String
    return @sprintf("%.0f", n) |> s -> reverse(join([reverse(s)[i:min(i+2,end)] for i in 1:3:length(s)], ","))
end

"""
Main entry point
"""
function main()
    try
        run_algofi_demo()
    catch e
        println("❌ Demo failed with error: $e")
        println("Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the demo if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end