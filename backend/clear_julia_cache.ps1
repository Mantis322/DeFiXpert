# Julia Cache Temizleme Script
# Bu dosyayı çalıştırarak Julia precompilation cache'ini temizleyebilirsiniz

Write-Host "Cleaning Julia compilation cache..." -ForegroundColor Yellow

# Julia precompiled dosyalarını temizle
$juliaCompiled = "$env:USERPROFILE\.julia\compiled"
if (Test-Path $juliaCompiled) {
    Write-Host "Removing compiled cache: $juliaCompiled" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $juliaCompiled -ErrorAction SilentlyContinue
}

# Scratchspaces temizle (isteğe bağlı)
$juliaScratch = "$env:USERPROFILE\.julia\scratchspaces"
if (Test-Path $juliaScratch) {
    Write-Host "Removing scratchspaces: $juliaScratch" -ForegroundColor Cyan
    Remove-Item -Recurse -Force $juliaScratch -ErrorAction SilentlyContinue
}

Write-Host "`nJulia cache cleared successfully!" -ForegroundColor Green
Write-Host "Now you can run Julia again without precompilation errors." -ForegroundColor Yellow

Write-Host "`nTo run the server:" -ForegroundColor White
Write-Host "julia --project=. run_server.jl" -ForegroundColor Cyan