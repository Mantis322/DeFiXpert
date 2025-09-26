#!/usr/bin/env julia

"""
Database Migration Script
Creates all necessary tables for JuliaOS Backend including Live Opportunities
"""

using LibPQ
using Printf
include("src/db/DBConfig.jl")

function run_migration()
    try
        println("🔌 Connecting to database...")
        conn_string = DBConfig.get_db_connection_string()
        conn = LibPQ.Connection(conn_string)
        
        # Read live opportunities migration file
        println("📋 Reading live opportunities migration file...")
        live_opportunities_sql = read("migrations/live_opportunities_schema.sql", String)
        
        # Execute live opportunities migration
        println("🚀 Running live opportunities migration...")
        result = LibPQ.execute(conn, live_opportunities_sql)
        
        println("✅ Live opportunities migration executed successfully!")
        
        # Check if tables were created
        check_sql = """
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name IN ('arbitrage_opportunities', 'strategy_performance_tracking', 'strategy_trades', 'price_feeds')
        ORDER BY table_name;
        """
        
        tables_result = LibPQ.execute(conn, check_sql)
        
        println("📊 Created tables:")
        for row in tables_result
            println("  - $(row[1])")
        end
        
        LibPQ.close(conn)
        println("\n🎉 Live opportunities migration completed successfully!")
        
    catch e
        println("\n❌ Migration failed: $e")
        rethrow(e)
    end
end

# Run the migration
run_migration()
        rethrow()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_migration()
end