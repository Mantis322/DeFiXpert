module FundRecoverySystem

using HTTP, JSON3
using LibPQ
using Dates

# Import existing modules
include("DeFiProtocolIntegration.jl")
using .DeFiProtocolIntegration

include("../../../julia/src/blockchain/AlgorandClient.jl")
using .AlgorandClient

"""
Fund Recovery & Security System
Critical module for ensuring users can always recover their funds from DeFi protocols
"""

# Database connection helper
function get_db_connection()
    return LibPQ.Connection("host=localhost port=5432 dbname=algofi_db user=postgres password=postgres")
end

"""
Get all user's active investments across all protocols
"""
function get_user_active_investments(wallet_address::String)
    try
        conn = get_db_connection()
        
        query = """
            SELECT 
                ui.id,
                ui.protocol_name,
                ui.staked_amount,
                ui.current_value,
                ui.stake_date,
                ui.last_updated,
                ui.stake_status,
                ui.withdrawal_delay_seconds,
                th.algorand_tx_id,
                th.metadata
            FROM user_investments ui
            LEFT JOIN transaction_history th ON th.id = (
                SELECT th2.id 
                FROM transaction_history th2 
                WHERE th2.wallet_address = ui.wallet_address 
                AND th2.metadata->>'protocol' = ui.protocol_name
                ORDER BY th2.created_at DESC 
                LIMIT 1
            )
            WHERE ui.wallet_address = \$1 
            AND ui.stake_status = 'active'
            ORDER BY ui.stake_date DESC
        """
        
        result = execute(conn, query, [wallet_address])
        investments = []
        
        for row in result
            investment = Dict(
                "id" => row[1],
                "protocol_name" => row[2],
                "staked_amount" => row[3],
                "current_value" => row[4],
                "stake_date" => row[5],
                "last_updated" => row[6],
                "stake_status" => row[7],
                "withdrawal_delay_seconds" => row[8],
                "algorand_tx_id" => row[9],
                "metadata" => row[10] !== nothing ? JSON3.read(row[10]) : Dict(),
                "withdrawal_available" => is_withdrawal_available(row[5], row[8])
            )
            push!(investments, investment)
        end
        
        close(conn)
        
        return Dict(
            "investments" => investments,
            "total_investments" => length(investments),
            "total_value" => sum(inv["current_value"] for inv in investments),
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Check if withdrawal is available for an investment (considering time locks)
"""
function is_withdrawal_available(stake_date, withdrawal_delay_seconds)
    try
        if withdrawal_delay_seconds === nothing || withdrawal_delay_seconds == 0
            return true  # No time lock
        end
        
        # Parse stake date and check if delay period has passed
        if stake_date === nothing
            return false
        end
        
        stake_time = DateTime(stake_date)
        delay_duration = Dates.Second(withdrawal_delay_seconds)
        unlock_time = stake_time + delay_duration
        
        return now() >= unlock_time
    catch
        return false  # Default to not available if there's any error
    end
end

"""
Create withdrawal transaction for a specific protocol investment
"""
function create_recovery_withdrawal_transaction(wallet_address::String, investment_id::Int64)
    try
        # Get investment details
        conn = get_db_connection()
        
        query = """
            SELECT protocol_name, staked_amount, current_value, withdrawal_delay_seconds, stake_date, stake_status
            FROM user_investments 
            WHERE id = \$1 AND wallet_address = \$2 AND stake_status = 'active'
        """
        
        result = execute(conn, query, [investment_id, wallet_address])
        
        if isempty(result)
            return Dict("error" => "Investment not found or already withdrawn", "status" => "error")
        end
        
        investment = collect(result)[1]
        protocol_name = investment[1]
        staked_amount = investment[2]
        current_value = investment[3] 
        withdrawal_delay = investment[4]
        stake_date = investment[5]
        stake_status = investment[6]
        
        close(conn)
        
        # Security Check: Verify withdrawal is allowed
        if !is_withdrawal_available(stake_date, withdrawal_delay)
            delay_hours = withdrawal_delay / 3600
            return Dict(
                "error" => "Withdrawal not yet available. Time lock: $delay_hours hours",
                "status" => "time_locked",
                "unlock_time" => stake_date + Dates.Second(withdrawal_delay)
            )
        end
        
        # Use current_value for withdrawal amount (includes any accrued interest)
        withdrawal_amount = Int64(current_value)
        
        # Create withdrawal transaction using DeFi integration
        withdrawal_result = DeFiProtocolIntegration.create_protocol_withdraw_transaction(
            protocol_name, wallet_address, withdrawal_amount
        )
        
        if withdrawal_result["status"] == "success"
            # Add investment-specific information
            withdrawal_result["investment_id"] = investment_id
            withdrawal_result["protocol"] = protocol_name
            withdrawal_result["original_stake"] = staked_amount
            withdrawal_result["recovery_amount"] = withdrawal_amount
        end
        
        return withdrawal_result
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Emergency withdrawal function - attempts to recover funds even if protocol is having issues
"""
function emergency_fund_recovery(wallet_address::String, investment_id::Int64, override_time_lock::Bool=false)
    try
        @warn "Emergency fund recovery initiated" wallet=wallet_address investment_id=investment_id
        
        # Get investment details
        conn = get_db_connection()
        
        query = """
            SELECT protocol_name, staked_amount, current_value, withdrawal_delay_seconds, stake_date, stake_status
            FROM user_investments 
            WHERE id = \$1 AND wallet_address = \$2
        """
        
        result = execute(conn, query, [investment_id, wallet_address])
        
        if isempty(result)
            return Dict("error" => "Investment not found", "status" => "error")
        end
        
        investment = collect(result)[1]
        protocol_name = investment[1]
        staked_amount = investment[2]
        current_value = investment[3]
        withdrawal_delay = investment[4]
        stake_date = investment[5]
        stake_status = investment[6]
        
        # Emergency Override Check
        if !override_time_lock && !is_withdrawal_available(stake_date, withdrawal_delay)
            return Dict(
                "error" => "Emergency recovery requested but time lock still active. Use override_time_lock=true for true emergency",
                "status" => "time_locked"
            )
        end
        
        # Try multiple recovery methods
        recovery_attempts = []
        
        # Method 1: Standard protocol withdrawal
        try
            standard_result = create_recovery_withdrawal_transaction(wallet_address, investment_id)
            push!(recovery_attempts, Dict("method" => "standard_withdrawal", "result" => standard_result))
            
            if standard_result["status"] == "success"
                @info "Standard withdrawal successful for emergency recovery"
                return standard_result
            end
        catch e
            push!(recovery_attempts, Dict("method" => "standard_withdrawal", "error" => string(e)))
        end
        
        # Method 2: Direct protocol API call (if available)
        try
            # This would require protocol-specific implementations
            # For now, we'll simulate this
            @warn "Attempting direct protocol recovery" protocol=protocol_name
            
            # Mark this attempt for manual review
            manual_review_query = """
                INSERT INTO manual_recovery_requests 
                (wallet_address, investment_id, protocol_name, amount, request_type, status, created_at)
                VALUES (\$1, \$2, \$3, \$4, 'emergency_recovery', 'pending', NOW())
            """
            
            execute(conn, manual_review_query, [
                wallet_address, investment_id, protocol_name, current_value
            ])
            
            push!(recovery_attempts, Dict(
                "method" => "manual_review_requested", 
                "status" => "pending_manual_review"
            ))
            
        catch e
            push!(recovery_attempts, Dict("method" => "manual_review", "error" => string(e)))
        end
        
        close(conn)
        
        # Return emergency recovery report
        return Dict(
            "status" => "emergency_recovery_initiated",
            "investment_id" => investment_id,
            "protocol" => protocol_name,
            "amount_at_risk" => current_value,
            "recovery_attempts" => recovery_attempts,
            "manual_review_requested" => true,
            "contact_support" => "Emergency recovery initiated. Our team will review within 24 hours."
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Complete withdrawal process and update database
"""
function complete_fund_recovery(wallet_address::String, investment_id::Int64, tx_id::String, confirmation_result::Dict)
    try
        conn = get_db_connection()
        
        if confirmation_result["confirmed"]
            # Update investment status to withdrawn
            update_query = """
                UPDATE user_investments 
                SET stake_status = 'withdrawn',
                    withdrawal_date = NOW(),
                    withdrawal_tx_id = \$3,
                    last_updated = NOW()
                WHERE id = \$1 AND wallet_address = \$2
            """
            
            execute(conn, update_query, [investment_id, wallet_address, tx_id])
            
            # Record withdrawal transaction
            record_query = """
                INSERT INTO transaction_history 
                (wallet_address, transaction_type, amount, algorand_tx_id, status, metadata, created_at)
                VALUES (\$1, 'protocol_withdrawal', \$2, \$3, 'confirmed', \$4, NOW())
                RETURNING id
            """
            
            # Get investment amount for the record
            investment_query = "SELECT current_value, protocol_name FROM user_investments WHERE id = \$1"
            inv_result = execute(conn, investment_query, [investment_id])
            inv_data = collect(inv_result)[1]
            
            metadata = JSON3.write(Dict(
                "investment_id" => investment_id,
                "protocol" => inv_data[2],
                "recovery_type" => "user_initiated",
                "confirmation_round" => get(confirmation_result, "confirmation_round", 0)
            ))
            
            execute(conn, record_query, [
                wallet_address, 
                inv_data[1],  # current_value
                tx_id, 
                metadata
            ])
            
            close(conn)
            
            return Dict(
                "status" => "recovery_complete",
                "investment_id" => investment_id,
                "transaction_id" => tx_id,
                "amount_recovered" => inv_data[1],
                "message" => "Funds successfully recovered"
            )
        else
            close(conn)
            return Dict(
                "status" => "recovery_failed",
                "investment_id" => investment_id,
                "error" => "Transaction confirmation failed"
            )
        end
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Get recovery status for all user investments
"""
function get_recovery_status(wallet_address::String)
    try
        investments_result = get_user_active_investments(wallet_address)
        
        if investments_result["status"] != "success"
            return investments_result
        end
        
        recovery_status = []
        
        for investment in investments_result["investments"]
            status = Dict(
                "investment_id" => investment["id"],
                "protocol" => investment["protocol_name"],
                "amount" => investment["current_value"],
                "can_withdraw_immediately" => investment["withdrawal_available"],
                "time_locked" => !investment["withdrawal_available"],
                "estimated_unlock_time" => if !investment["withdrawal_available"] && investment["withdrawal_delay_seconds"] > 0
                    investment["stake_date"] + Dates.Second(investment["withdrawal_delay_seconds"])
                else
                    nothing
                end,
                "risk_level" => assess_protocol_risk(investment["protocol_name"])
            )
            
            push!(recovery_status, status)
        end
        
        return Dict(
            "wallet_address" => wallet_address,
            "recovery_status" => recovery_status,
            "total_recoverable_amount" => sum(s["amount"] for s in recovery_status),
            "immediately_available" => sum(s["amount"] for s in recovery_status if s["can_withdraw_immediately"]),
            "time_locked_amount" => sum(s["amount"] for s in recovery_status if s["time_locked"]),
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Assess protocol risk level for recovery purposes
"""
function assess_protocol_risk(protocol_name::String)
    # This would ideally connect to real-time protocol health APIs
    # For now, return static risk assessments
    protocol_risks = Dict(
        "tinyman" => "medium",
        "algofi" => "low", 
        "pact" => "high"
    )
    
    return get(protocol_risks, protocol_name, "unknown")
end

end # module