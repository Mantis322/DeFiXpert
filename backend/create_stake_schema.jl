using LibPQ

println("Creating stake schema...")

conn = LibPQ.Connection("host=localhost port=5432 dbname=algofi_db user=postgres password=postgres")

schema_sql = read("migrations/stake_schema.sql", String)
execute(conn, schema_sql)

close(conn)

println("✅ Stake schema created successfully")