# PostgreSQL Environment Variables
# Bu dosyayı çalıştırarak environment variables ayarlayın

# PostgreSQL şifrenizi buraya girin
$env:DB_PASSWORD = "postgres"  # Gerçek şifrenizi buraya yazın
$env:PGPASSWORD = "postgres"   # psql için de geçerli olacak

# Diğer database ayarları (isteğe bağlı)
$env:DB_HOST = "localhost"
$env:DB_PORT = "5432" 
$env:DB_NAME = "algofi_db"
$env:DB_USER = "postgres"

Write-Host "Environment variables set successfully!" -ForegroundColor Green
Write-Host "DB_PASSWORD: $env:DB_PASSWORD"
Write-Host "PGPASSWORD: $env:PGPASSWORD"
Write-Host "DB_HOST: $env:DB_HOST"
Write-Host "DB_PORT: $env:DB_PORT"
Write-Host "DB_NAME: $env:DB_NAME"
Write-Host "DB_USER: $env:DB_USER"

Write-Host "`nNow you can run Julia without password prompts!" -ForegroundColor Yellow