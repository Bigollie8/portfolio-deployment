<#
.SYNOPSIS
    Quick deployment helper - simplified interface for agents.

.DESCRIPTION
    Provides simple one-liner deployments for common scenarios.
    Wraps the main deploy.ps1 script with sensible defaults.

.EXAMPLE
    .\quick-deploy.ps1 portfolio
    Deploy the portfolio frontend

.EXAMPLE
    .\quick-deploy.ps1 all-frontends
    Deploy all frontend services

.EXAMPLE
    .\quick-deploy.ps1 list
    Show all available services
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "help"
)

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Help {
    Write-Host ""
    Write-Host "Quick Deploy - Simplified Deployment Commands" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\quick-deploy.ps1 <command>" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Frontend Commands:"
    Write-Host "  portfolio        Deploy portfolio frontend (terminal-portfolio)"
    Write-Host "  photos           Deploy photos frontend (rapidPhotoFlow)"
    Write-Host "  security         Deploy security frontend (basedSecurity_AI)"
    Write-Host "  shipping         Deploy shipping frontend (shippingMonitoring)"
    Write-Host "  all-frontends    Deploy all frontend services"
    Write-Host ""
    Write-Host "Backend Commands:"
    Write-Host "  portfolio-backend    Deploy portfolio backend"
    Write-Host "  photos-backend       Deploy photos backend"
    Write-Host "  security-backend     Deploy security backend"
    Write-Host "  shipping-backend     Deploy shipping backend"
    Write-Host "  status-page          Deploy status page"
    Write-Host "  all-backends         Deploy all backend services"
    Write-Host ""
    Write-Host "Other Commands:"
    Write-Host "  all              Deploy everything (frontends + backends)"
    Write-Host "  list             List all services and their status"
    Write-Host "  help             Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\quick-deploy.ps1 portfolio" -ForegroundColor Green
    Write-Host "  .\quick-deploy.ps1 all-frontends" -ForegroundColor Green
    Write-Host ""
}

function Show-Services {
    Write-Host ""
    Write-Host "Available Services" -ForegroundColor Cyan
    Write-Host "==================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Frontends:" -ForegroundColor Yellow
    Write-Host "  portfolio    https://portfolio.basedsecurity.net"
    Write-Host "  photos       https://photos.basedsecurity.net"
    Write-Host "  security     https://security.basedsecurity.net"
    Write-Host "  shipping     https://shipping.basedsecurity.net"
    Write-Host ""
    Write-Host "Backends:" -ForegroundColor Yellow
    Write-Host "  portfolio-backend"
    Write-Host "  photos-backend"
    Write-Host "  security-backend"
    Write-Host "  shipping-backend"
    Write-Host "  status-page"
    Write-Host ""
    Write-Host "API Endpoint: https://api.basedsecurity.net" -ForegroundColor Green
    Write-Host ""
}

switch ($Command.ToLower()) {
    "help" { Show-Help }
    "list" { Show-Services }
    "all-frontends" {
        & "$SCRIPT_DIR\deploy.ps1" -Service frontends
    }
    "all-backends" {
        & "$SCRIPT_DIR\deploy.ps1" -Service backends
    }
    "all" {
        & "$SCRIPT_DIR\deploy.ps1" -Service all
    }
    { $_ -in @('portfolio', 'photos', 'security', 'shipping') } {
        & "$SCRIPT_DIR\deploy.ps1" -Service $Command
    }
    { $_ -in @('portfolio-backend', 'photos-backend', 'security-backend', 'shipping-backend', 'status-page') } {
        & "$SCRIPT_DIR\deploy.ps1" -Service $Command
    }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host "Run '.\quick-deploy.ps1 help' for available commands."
        exit 1
    }
}
