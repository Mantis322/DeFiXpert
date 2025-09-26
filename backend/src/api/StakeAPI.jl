module StakeAPI

using HTTP, JSON3
using LibPQ
using Dates

# Import AI Strategy API
include("AIStrategyAPI.jl")
using .AIStrategyAPI

# Import DeFi Protocol Integration
include("DeFiProtocolIntegration.jl")
using .DeFiProtocolIntegration

# Import Fund Recovery System
include("FundRecoverySystem.jl")
using .FundRecoverySystem

# Stake işlemleri için API endpoint'leri

# Database connection helper (direct connection without DBConfig)
function get_db_connection()
    return LibPQ.Connection("host=localhost port=5432 dbname=algofi_db user=postgres password=postgres")
end

# Helper function to convert result to array of dicts
function result_to_dicts(result)
    dicts = []
    for row in result
        dict = Dict()
        for (i, name) in enumerate(result.column_names)
            dict[String(name)] = row[i]
        end
        push!(dicts, dict)
    end
    return dicts
end

"""
Kullanıcının stake edebileceği maksimum miktarı hesapla
"""
function calculate_stakeable_amount(wallet_address::String)
    try
        conn = get_db_connection()
        
        # Kullanıcının mevcut stake durumunu kontrol et
        query = """
            SELECT COALESCE(SUM(staked_amount), 0) as total_staked,
                   COALESCE(SUM(available_balance), 0) as available_balance
            FROM user_investments 
            WHERE wallet_address = \$1 AND stake_status = 'active'
        """
        
        result = execute(conn, query, [wallet_address])
        row = collect(result)[1]
        
        close(conn)
        
        return Dict(
            "total_staked" => row[1],
            "available_balance" => row[2],
            "status" => "success"
        )
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Algorand stake etme işlemi
"""
function stake_algo(wallet_address::String, amount::Int64, ai_strategy_id::Union{Int64, Nothing} = nothing)
    try
        conn = get_db_connection()
        
        # Minimum stake miktarını kontrol et
        config_query = "SELECT min_stake_amount, max_stake_amount FROM stake_configs ORDER BY id DESC LIMIT 1"
        config_result = execute(conn, config_query)
        config_row = collect(config_result)[1]
        
        if amount < config_row[1]
            return Dict(
                "error" => "Minimum stake miktarı $(config_row[1]) microALGO",
                "status" => "error"
            )
        end
        
        if amount > config_row[2]
            return Dict(
                "error" => "Maksimum stake miktarı $(config_row[2]) microALGO",
                "status" => "error"
            )
        end
        
        # Kullanıcı var mı kontrol et
        user_query = "SELECT wallet_address FROM users WHERE wallet_address = \$1"
        user_result = execute(conn, user_query, [wallet_address])
        user_rows = collect(user_result)
        
        if isempty(user_rows)
            return Dict("error" => "Kullanıcı bulunamadı", "status" => "error")
        end
        
        # Yeni yatırım kaydı oluştur
        insert_query = """
            INSERT INTO user_investments (wallet_address, staked_amount, ai_strategy_id, stake_status)
            VALUES (\$1, \$2, \$3, 'active')
            RETURNING id
        """
        
        insert_result = execute(conn, insert_query, [wallet_address, amount, ai_strategy_id])
        investment_id = collect(insert_result)[1][1]
        
        # Transaction geçmişine kaydet
        tx_query = """
            INSERT INTO transaction_history (wallet_address, investment_id, transaction_type, amount, status)
            VALUES (\$1, \$2, 'stake', \$3, 'confirmed')
        """
        
        execute(conn, tx_query, [wallet_address, investment_id, amount])
        
        close(conn)
        
        return Dict(
            "investment_id" => investment_id,
            "staked_amount" => amount,
            "message" => "Başarıyla stake edildi",
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Stake edilen miktarı çekme işlemi
"""
function withdraw_stake(wallet_address::String, investment_id::Int64, amount::Int64)
    try
        conn = get_db_connection()
        
        # Yatırım bilgilerini kontrol et
        check_query = """
            SELECT ui.id, ui.staked_amount, ui.available_balance, ui.stake_status,
                   sc.withdrawal_fee_percentage
            FROM user_investments ui, stake_configs sc
            WHERE ui.id = \$1 AND ui.wallet_address = \$2 AND ui.stake_status = 'active'
            ORDER BY sc.id DESC LIMIT 1
        """
        
        check_result = execute(conn, check_query, [investment_id, wallet_address])
        check_rows = collect(check_result)
        
        if isempty(check_rows)
            return Dict("error" => "Yatırım bulunamadı veya aktif değil", "status" => "error")
        end
        
        investment_row = check_rows[1]
        
        # Çekilebilir miktar kontrolü
        available = investment_row[3]  # available_balance
        if amount > available
            return Dict(
                "error" => "Yetersiz bakiye. Çekilebilir miktar: $available microALGO",
                "status" => "error"
            )
        end
        
        # Çekim ücreti hesapla
        withdrawal_fee = round(Int64, amount * investment_row[5])  # withdrawal_fee_percentage
        net_amount = amount - withdrawal_fee
        
        # Bakiyeleri güncelle
        update_query = """
            UPDATE user_investments 
            SET available_balance = available_balance - \$1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = \$2
        """
        
        execute(conn, update_query, [amount, investment_id])
        
        # Transaction geçmişine kaydet
        tx_query = """
            INSERT INTO transaction_history (wallet_address, investment_id, transaction_type, amount, status)
            VALUES (\$1, \$2, 'withdraw', \$3, 'confirmed')
        """
        
        execute(conn, tx_query, [wallet_address, investment_id, net_amount])
        
        close(conn)
        
        return Dict(
            "withdrawn_amount" => net_amount,
            "withdrawal_fee" => withdrawal_fee,
            "message" => "Başarıyla çekildi",
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Kullanıcının toplam yatırım bilgilerini getir
"""
function get_user_investments(wallet_address::String)
    try
        conn = get_db_connection()
        
        query = """
            SELECT ui.id, ui.staked_amount, ui.available_balance, ui.total_earnings,
                   ui.ai_strategy_id, ui.stake_status, ui.created_at,
                   asp.strategy_name, asp.daily_return_percentage, asp.risk_level
            FROM user_investments ui
            LEFT JOIN ai_strategy_performance asp ON ui.ai_strategy_id = asp.id
            WHERE ui.wallet_address = \$1
            ORDER BY ui.created_at DESC
        """
        
        result = execute(conn, query, [wallet_address])
        investments = result_to_dicts(result)
        
        close(conn)
        
        return Dict(
            "investments" => investments,
            "total_count" => length(investments),
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Transaction geçmişini getir
"""
function get_transaction_history(wallet_address::String, limit::Int64 = 50)
    try
        conn = get_db_connection()
        
        query = """
            SELECT th.id, th.transaction_type, th.amount, th.algorand_tx_id, 
                   th.status, th.created_at, th.confirmed_at,
                   ui.id as investment_id
            FROM transaction_history th
            JOIN user_investments ui ON th.investment_id = ui.id
            WHERE ui.wallet_address = \$1
            ORDER BY th.created_at DESC
            LIMIT \$2
        """
        
        result = execute(conn, query, [wallet_address, limit])
        transactions = result_to_dicts(result)
        
        close(conn)
        
        return Dict(
            "transactions" => transactions,
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
AI strateji performanslarını getir
"""
function get_ai_strategies()
    try
        conn = get_db_connection()
        
        query = """
            SELECT id, strategy_name, daily_return_percentage, weekly_return_percentage,
                   monthly_return_percentage, success_rate, risk_level, 
                   active_investors_count, total_managed_amount
            FROM ai_strategy_performance
            ORDER BY monthly_return_percentage DESC
        """
        
        result = execute(conn, query)
        strategies = result_to_dicts(result)
        
        close(conn)
        
        return Dict(
            "strategies" => strategies,
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Günlük faiz hesaplama ve dağıtma (background task)
"""
function distribute_daily_rewards()
    try
        conn = get_db_connection()
        
        # Aktif yatırımları al
        query = """
            SELECT ui.id, ui.wallet_address, ui.staked_amount, ui.ai_strategy_id,
                   sc.daily_interest_rate, sc.ai_profit_share_percentage,
                   asp.daily_return_percentage
            FROM user_investments ui
            JOIN stake_configs sc ON true
            LEFT JOIN ai_strategy_performance asp ON ui.ai_strategy_id = asp.id
            WHERE ui.stake_status = 'active' AND ui.staked_amount > 0
            ORDER BY sc.id DESC
        """
        
        result = execute(conn, query)
        investments = result_to_dicts(result)
        
        for investment in investments
            # Temel faiz hesapla
            staked_amount = investment["staked_amount"]
            daily_rate = investment["daily_interest_rate"]
            base_interest = round(Int64, staked_amount * daily_rate)
            
            # AI strateji bonusu hesapla
            ai_bonus = 0
            if !isnothing(investment["ai_strategy_id"]) && !isnothing(investment["daily_return_percentage"])
                ai_return = round(Int64, staked_amount * investment["daily_return_percentage"])
                ai_bonus = round(Int64, ai_return * investment["ai_profit_share_percentage"])
            end
            
            total_reward = base_interest + ai_bonus
            
            if total_reward > 0
                # Available balance'ı güncelle
                update_query = """
                    UPDATE user_investments 
                    SET available_balance = available_balance + \$1,
                        total_earnings = total_earnings + \$2,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = \$3
                """
                
                execute(conn, update_query, [total_reward, total_reward, investment["id"]])
                
                # Transaction kaydı oluştur
                tx_query = """
                    INSERT INTO transaction_history (wallet_address, investment_id, transaction_type, amount, status)
                    VALUES (\$1, \$2, 'profit', \$3, 'confirmed')
                """
                
                execute(conn, tx_query, [investment["wallet_address"], investment["id"], total_reward])
            end
        end
        
        close(conn)
        
        return Dict(
            "processed_investments" => length(investments),
            "message" => "Günlük ödüller dağıtıldı",
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
AI Strategy Recommendation Endpoint - Get personalized DeFi protocol recommendations
"""
function get_ai_strategy_recommendation(wallet_address::String, amount_microalgo::Int64, risk_preference::String="medium")
    return AIStrategyAPI.get_ai_recommendation(wallet_address, amount_microalgo, risk_preference)
end

"""
Protocol Safety Validation Endpoint - Validate protocol before transaction
"""
function validate_protocol_safety_endpoint(protocol_name::String, amount_microalgo::Int64)
    return AIStrategyAPI.validate_protocol_safety(protocol_name, amount_microalgo)
end

"""
Create Protocol Transaction Record Endpoint
"""
function create_protocol_transaction_endpoint(wallet_address::String, protocol_name::String, amount_microalgo::Int64, algorand_tx_id::String="")
    return AIStrategyAPI.create_protocol_transaction_record(wallet_address, protocol_name, amount_microalgo, algorand_tx_id)
end

"""
Get Available DeFi Protocols List
"""
function get_available_protocols()
    try
        protocols = []
        
        for (protocol_key, protocol_info) in AIStrategyAPI.DEFI_PROTOCOLS
            push!(protocols, Dict(
                "id" => protocol_key,
                "name" => protocol_info["name"],
                "risk_level" => protocol_info["risk_level"],
                "estimated_apy" => protocol_info["estimated_apy"],
                "min_deposit_algo" => protocol_info["min_deposit"] / 1000000,  # Convert to ALGO
                "max_deposit_algo" => protocol_info["max_deposit"] / 1000000,  # Convert to ALGO
                "withdraw_delay_hours" => protocol_info["withdraw_delay"] / 3600  # Convert to hours
            ))
        end
        
        return Dict(
            "protocols" => protocols,
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Real DeFi Protocol Transaction Endpoints for secure fund management
"""

"""
Create Protocol Deposit Transaction - Creates unsigned transaction for user to sign
"""
function create_protocol_deposit_tx_endpoint(protocol_name::String, wallet_address::String, amount_microalgo::Int64)
    try
        # First validate the transaction
        validation = DeFiProtocolIntegration.validate_protocol_transaction(
            protocol_name, wallet_address, amount_microalgo, "deposit"
        )
        
        if !validation["valid"]
            return Dict(
                "error" => validation["reason"],
                "status" => "validation_failed"
            )
        end
        
        # Create the unsigned transaction
        result = DeFiProtocolIntegration.create_protocol_deposit_transaction(
            protocol_name, wallet_address, amount_microalgo
        )
        
        # Add validation info to response
        if result["status"] == "success"
            result["validation"] = validation
        end
        
        return result
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Create Protocol Withdraw Transaction - Creates unsigned transaction for user to sign  
"""
function create_protocol_withdraw_tx_endpoint(protocol_name::String, wallet_address::String, amount_microalgo::Int64)
    try
        # First validate the withdrawal (different validation rules)
        validation = DeFiProtocolIntegration.validate_protocol_transaction(
            protocol_name, wallet_address, amount_microalgo, "withdraw"
        )
        
        if !validation["valid"]
            return Dict(
                "error" => validation["reason"],
                "status" => "validation_failed"
            )
        end
        
        # Create the unsigned withdrawal transaction
        result = DeFiProtocolIntegration.create_protocol_withdraw_transaction(
            protocol_name, wallet_address, amount_microalgo
        )
        
        # Add validation info to response
        if result["status"] == "success"
            result["validation"] = validation
        end
        
        return result
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Submit Signed Protocol Transaction - Submits user-signed transaction to network
"""
function submit_protocol_transaction_endpoint(signed_transaction::String)
    try
        # Submit the signed transaction
        result = DeFiProtocolIntegration.submit_protocol_transaction(signed_transaction)
        
        return result
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Wait for Protocol Transaction Confirmation
"""
function wait_protocol_confirmation_endpoint(tx_id::String, timeout_seconds::Int=30)
    try
        result = DeFiProtocolIntegration.wait_for_protocol_transaction_confirmation(tx_id, timeout_seconds)
        
        return result
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Complete Protocol Transaction Flow - Handles full transaction lifecycle for security
"""
function complete_protocol_transaction_endpoint(wallet_address::String, protocol_name::String, amount_microalgo::Int64, signed_transaction::String)
    try
        # Step 1: Final validation before submission
        validation = DeFiProtocolIntegration.validate_protocol_transaction(
            protocol_name, wallet_address, amount_microalgo, "deposit"
        )
        
        if !validation["valid"]
            return Dict(
                "error" => "Final validation failed: " * validation["reason"],
                "status" => "validation_failed"
            )
        end
        
        # Step 2: Submit transaction
        submit_result = DeFiProtocolIntegration.submit_protocol_transaction(signed_transaction)
        
        if submit_result["status"] != "submitted"
            return submit_result  # Return error from submission
        end
        
        tx_id = submit_result["transaction_id"]
        
        # Step 3: Record transaction in database BEFORE confirmation
        record_result = create_protocol_transaction_endpoint(wallet_address, protocol_name, amount_microalgo, tx_id)
        
        if record_result["status"] != "success"
            @warn "Transaction submitted but database record failed" tx_id=tx_id protocol=protocol_name
            # Continue anyway - transaction is submitted
        end
        
        # Step 4: Wait for confirmation
        confirmation_result = DeFiProtocolIntegration.wait_for_protocol_transaction_confirmation(tx_id, 60)  # 60 second timeout
        
        if confirmation_result["confirmed"]
            # Step 5: Update database record to confirmed
            conn = get_db_connection()
            try
                update_query = """
                    UPDATE transaction_history 
                    SET status = 'confirmed', 
                        metadata = jsonb_set(metadata, '{confirmation_round}', to_jsonb(\$1)),
                        updated_at = NOW()
                    WHERE algorand_tx_id = \$2
                """
                execute(conn, update_query, [confirmation_result["confirmation_round"], tx_id])
                close(conn)
            catch db_e
                @warn "Failed to update confirmation status" tx_id=tx_id error=string(db_e)
            end
        end
        
        # Return complete result
        return Dict(
            "transaction_id" => tx_id,
            "protocol" => protocol_name,
            "amount" => amount_microalgo,
            "submission_status" => submit_result["status"],
            "confirmation_status" => confirmation_result["status"],
            "confirmed" => confirmation_result["confirmed"],
            "confirmation_round" => get(confirmation_result, "confirmation_round", 0),
            "database_record_id" => get(record_result, "transaction_id", 0),
            "status" => confirmation_result["confirmed"] ? "success" : "pending_confirmation"
        )
        
    catch e
        @error "Complete protocol transaction error" error=string(e)
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Fund Recovery & Security System Endpoints
"""

"""
Get User Active Investments for Recovery
"""
function get_user_active_investments_endpoint(wallet_address::String)
    return FundRecoverySystem.get_user_active_investments(wallet_address)
end

"""
Create Recovery Withdrawal Transaction
"""
function create_recovery_withdrawal_endpoint(wallet_address::String, investment_id::Int64)
    return FundRecoverySystem.create_recovery_withdrawal_transaction(wallet_address, investment_id)
end

"""
Emergency Fund Recovery
"""
function emergency_fund_recovery_endpoint(wallet_address::String, investment_id::Int64, override_time_lock::Bool=false)
    return FundRecoverySystem.emergency_fund_recovery(wallet_address, investment_id, override_time_lock)
end

"""
Complete Fund Recovery Process
"""
function complete_fund_recovery_endpoint(wallet_address::String, investment_id::Int64, tx_id::String, confirmation_result::Dict)
    return FundRecoverySystem.complete_fund_recovery(wallet_address, investment_id, tx_id, confirmation_result)
end

"""
Get Recovery Status for All User Investments
"""
function get_recovery_status_endpoint(wallet_address::String)
    return FundRecoverySystem.get_recovery_status(wallet_address)
end

"""
Get real AI strategies from database
"""
function get_real_ai_strategies()
    try
        conn = get_db_connection()
        
        query = """
            SELECT id, strategy_name, total_managed_amount, daily_return_percentage,
                   weekly_return_percentage, monthly_return_percentage, success_rate,
                   risk_level, active_investors_count, created_at, updated_at
            FROM ai_strategy_performance
            ORDER BY success_rate DESC, monthly_return_percentage DESC
        """
        
        result = execute(conn, query)
        strategies = []
        
        for row in result
            strategy = Dict(
                "id" => row[1],
                "strategy_name" => row[2],
                "total_managed_amount" => row[3],
                "daily_return_percentage" => Float64(row[4]),
                "weekly_return_percentage" => Float64(row[5]),
                "monthly_return_percentage" => Float64(row[6]),
                "success_rate" => Float64(row[7]),
                "risk_level" => row[8],
                "active_investors_count" => row[9],
                "created_at" => row[10],
                "updated_at" => row[11]
            )
            push!(strategies, strategy)
        end
        
        close(conn)
        
        return Dict(
            "strategies" => strategies,
            "status" => "success"
        )
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

"""
Update AI strategy performance with real data
"""
function update_strategy_performance(strategy_id::Int64, performance_data::Dict)
    try
        conn = get_db_connection()
        
        query = """
            UPDATE ai_strategy_performance 
            SET total_managed_amount = COALESCE(\$2, total_managed_amount),
                daily_return_percentage = COALESCE(\$3, daily_return_percentage),
                weekly_return_percentage = COALESCE(\$4, weekly_return_percentage),
                monthly_return_percentage = COALESCE(\$5, monthly_return_percentage),
                success_rate = COALESCE(\$6, success_rate),
                active_investors_count = COALESCE(\$7, active_investors_count),
                updated_at = NOW()
            WHERE id = \$1
        """
        
        execute(conn, query, [
            strategy_id,
            get(performance_data, "total_managed_amount", nothing),
            get(performance_data, "daily_return_percentage", nothing),
            get(performance_data, "weekly_return_percentage", nothing),
            get(performance_data, "monthly_return_percentage", nothing),
            get(performance_data, "success_rate", nothing),
            get(performance_data, "active_investors_count", nothing)
        ])
        
        close(conn)
        
        return Dict("status" => "success", "message" => "Strategy performance updated")
        
    catch e
        return Dict("error" => string(e), "status" => "error")
    end
end

end # module