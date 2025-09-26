using LibPQ

println("Checking users table...")
conn = LibPQ.Connection("host=localhost port=5432 dbname=algofi_db user=postgres password=postgres")

# Users tablosunun var olup olmadığını kontrol et
result = execute(conn, "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users';")

println("Users table columns:")
for row in result
    println("  - $(row[1]): $(row[2])")
end

# Tüm tabloları listele
println("\nAll tables in database:")
result2 = execute(conn, "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';")

for row in result2
    println("  - $(row[1])")
end

close(conn)