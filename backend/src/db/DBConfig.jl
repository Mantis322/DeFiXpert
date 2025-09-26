__precompile__(false)  # Disable precompilation for dynamic config

module DBConfig

export get_db_connection_string, get_db_config

# Database configuration with environment variable support
const DB_HOST = get(ENV, "DB_HOST", "localhost")
const DB_PORT = parse(Int, get(ENV, "DB_PORT", "5432"))
const DB_NAME = get(ENV, "DB_NAME", "algofi_db")
const DB_USER = get(ENV, "DB_USER", "postgres")

# Try to get password from environment variable, fallback to default
function get_db_password()
    return get(ENV, "DB_PASSWORD", get(ENV, "PGPASSWORD", "postgres"))
end

"""
Get PostgreSQL connection string for LibPQ
"""
function get_db_connection_string()
    password = get_db_password()
    return "host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER password=$password"
end

"""
Get database configuration as a dictionary
"""
function get_db_config()
    return Dict(
        "host" => DB_HOST,
        "port" => DB_PORT,
        "database" => DB_NAME,
        "user" => DB_USER,
        "password" => get_db_password()
    )
end

end # module DBConfig