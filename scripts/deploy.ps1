<#
.SYNOPSIS
    Unified deployment script for all portfolio services.

.DESCRIPTION
    Deploys frontend and/or backend services to AWS infrastructure.
    Can deploy individual services or all services at once.

.PARAMETER Service
    The service to deploy. Options:
    - all: Deploy all services
    - frontends: Deploy all frontend services
    - backends: Deploy all backend services
    - portfolio: Deploy portfolio frontend
    - photos: Deploy photos frontend
    - security: Deploy security frontend
    - shipping: Deploy shipping frontend
    - portfolio-backend: Deploy portfolio backend
    - photos-backend: Deploy photos backend
    - security-backend: Deploy security backend
    - shipping-backend: Deploy shipping backend
    - status-page: Deploy status page

.PARAMETER SkipBuild
    Skip the build step (use existing dist/build folder)

.PARAMETER SkipInvalidation
    Skip CloudFront cache invalidation

.EXAMPLE
    .\deploy.ps1 -Service portfolio
    Deploy only the portfolio frontend

.EXAMPLE
    .\deploy.ps1 -Service frontends
    Deploy all frontend services

.EXAMPLE
    .\deploy.ps1 -Service all
    Deploy everything

.EXAMPLE
    .\deploy.ps1 -Service portfolio -SkipBuild
    Deploy portfolio frontend without rebuilding
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('all', 'frontends', 'backends', 'portfolio', 'photos', 'security', 'shipping',
                 'portfolio-backend', 'photos-backend', 'security-backend', 'shipping-backend', 'status-page')]
    [string]$Service,

    [switch]$SkipBuild,
    [switch]$SkipInvalidation,
    [switch]$DryRun,  # Simulate deployment without actually deploying

    [string]$Message = ""  # Optional deployment notes for Discord notification
)

# Configuration
$ErrorActionPreference = "Stop"
$DOMAIN = "basedsecurity.net"
$AWS_REGION = "us-east-1"
$EC2_HOST = "98.88.74.174"
$EC2_USER = "ec2-user"
$SSH_KEY = "$env:USERPROFILE\.ssh\terminal-portfolio-deploy.pem"

# Base paths (relative to this script)
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPOS_DIR = Split-Path -Parent (Split-Path -Parent $SCRIPT_DIR)

# Frontend configurations
$FRONTENDS = @{
    'portfolio' = @{
        Path = "$REPOS_DIR\terminal-portfolio\frontend"
        S3Bucket = "portfolio-prod-portfolio-frontend"
        CloudFrontId = "E15VHZ20NOJ0RE"
        BuildCmd = "npm run build"
        DistDir = "dist"
    }
    'photos' = @{
        Path = "$REPOS_DIR\rapidPhotoFlow\frontend"
        S3Bucket = "portfolio-prod-photos-frontend"
        CloudFrontId = "E3G0IS14XDZD1G"
        BuildCmd = "npm run build"
        DistDir = "dist"
    }
    'security' = @{
        Path = "$REPOS_DIR\basedSecurity_AI\web"
        S3Bucket = "portfolio-prod-security-frontend"
        CloudFrontId = "E3THVDXE9Y0OUH"
        BuildCmd = "npm run build"
        DistDir = "dist"
    }
    'shipping' = @{
        Path = "$REPOS_DIR\shippingMonitoring\client"
        S3Bucket = "portfolio-prod-shipping-frontend"
        CloudFrontId = "E2KOLBNNUKT40T"
        BuildCmd = "npm run build"
        DistDir = "dist"
    }
}

# Backend configurations
$BACKENDS = @{
    'portfolio-backend' = @{
        Path = "$REPOS_DIR\terminal-portfolio\backend"
        Image = "portfolio-backend"
        Container = "portfolio-backend"
    }
    'photos-backend' = @{
        Path = "$REPOS_DIR\rapidPhotoFlow\backend"
        Image = "photos-backend"
        Container = "photos-backend"
    }
    'security-backend' = @{
        Path = "$REPOS_DIR\basedSecurity_AI\api"
        Image = "security-backend"
        Container = "security-backend"
    }
    'shipping-backend' = @{
        Path = "$REPOS_DIR\shippingMonitoring\server"
        Image = "shipping-backend"
        Container = "shipping-backend"
    }
    'status-page' = @{
        Path = "$REPOS_DIR\status-page"
        Image = "status-page"
        Container = "status-page"
    }
}

# Colors for output
function Write-ColorOutput {
    param([string]$Color, [string]$Message)
    $colors = @{
        'Green' = 'Green'
        'Yellow' = 'Yellow'
        'Red' = 'Red'
        'Cyan' = 'Cyan'
    }
    Write-Host $Message -ForegroundColor $colors[$Color]
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput 'Cyan' "========================================"
    Write-ColorOutput 'Cyan' "  $Title"
    Write-ColorOutput 'Cyan' "========================================"
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput 'Green' "[OK] $Message"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput 'Yellow' "[WARN] $Message"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput 'Red' "[ERROR] $Message"
}

# Load Discord configuration from deploy-config.json
function Get-DiscordConfig {
    $configPath = Join-Path $SCRIPT_DIR "deploy-config.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json
        return $config.discord
    }
    return $null
}

# Get the webhook URL from config or environment variable
function Get-DiscordWebhookUrl {
    $config = Get-DiscordConfig
    if ($config -and $config.webhookUrl) {
        return $config.webhookUrl
    }
    return $env:DISCORD_DEPLOY_WEBHOOK
}

# Check if Discord notifications are enabled
function Test-DiscordEnabled {
    $config = Get-DiscordConfig
    if ($config) {
        return $config.enabled -eq $true
    }
    return $false
}

# Get git info from a repository path
function Get-GitInfo {
    param([string]$RepoPath)

    if (-not (Test-Path $RepoPath)) {
        return "No git info available"
    }

    Push-Location $RepoPath
    try {
        $gitDir = Join-Path $RepoPath ".git"
        if (-not (Test-Path $gitDir)) {
            # Check parent directories for git repo
            $parent = Split-Path -Parent $RepoPath
            while ($parent -and -not (Test-Path (Join-Path $parent ".git"))) {
                $parent = Split-Path -Parent $parent
            }
            if ($parent) {
                Push-Location $parent
            }
        }

        $commitInfo = git log -1 --format="%h - %s" 2>$null
        if ($LASTEXITCODE -eq 0 -and $commitInfo) {
            return $commitInfo
        }
        return "No git info available"
    }
    catch {
        return "No git info available"
    }
    finally {
        Pop-Location
    }
}

# Send Discord notification
function Send-DiscordNotification {
    param(
        [string]$ServiceName,
        [string]$ServiceType,  # "Frontend" or "Backend"
        [string]$ServiceUrl = "",
        [string]$GitInfo = "",
        [string]$CustomMessage = "",
        [bool]$Success = $true
    )

    if (-not (Test-DiscordEnabled)) {
        return
    }

    $webhookUrl = Get-DiscordWebhookUrl
    if (-not $webhookUrl) {
        Write-Warning "Discord webhook URL not configured. Set it in deploy-config.json or DISCORD_DEPLOY_WEBHOOK env var."
        return
    }

    # Build embed
    $color = if ($Success) { 2278621 } else { 15548997 }  # Green or Red in decimal
    $statusEmoji = if ($Success) { [char]0x2705 } else { [char]0x274C }  # Checkmark or X

    $fields = [System.Collections.ArrayList]@()
    [void]$fields.Add(@{ name = "Service"; value = $ServiceName; inline = [bool]$true })
    [void]$fields.Add(@{ name = "Type"; value = $ServiceType; inline = [bool]$true })

    if ($ServiceUrl) {
        [void]$fields.Add(@{ name = "URL"; value = $ServiceUrl; inline = [bool]$false })
    }

    if ($GitInfo -and $GitInfo -ne "No git info available") {
        [void]$fields.Add(@{ name = "Changes"; value = $GitInfo; inline = [bool]$false })
    }

    if ($CustomMessage) {
        [void]$fields.Add(@{ name = "Notes"; value = $CustomMessage; inline = [bool]$false })
    }

    $embed = @{
        title = "$statusEmoji Deployment: $ServiceName"
        color = $color
        fields = $fields.ToArray()
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        footer = @{
            text = "Portfolio Deployment"
        }
    }

    $payload = @{
        embeds = @($embed)
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "application/json" -Body $payload | Out-Null
        Write-Success "Discord notification sent"
    }
    catch {
        Write-Warning "Failed to send Discord notification: $($_.Exception.Message)"
    }
}

# Send deployment summary to Discord
function Send-DiscordSummary {
    param(
        [array]$Deployed,
        [array]$Failed,
        [string]$CustomMessage = ""
    )

    if (-not (Test-DiscordEnabled)) {
        return
    }

    $webhookUrl = Get-DiscordWebhookUrl
    if (-not $webhookUrl) {
        return
    }

    $allSuccess = $Failed.Count -eq 0
    $color = if ($allSuccess) { 2278621 } else { 15548997 }
    $title = if ($allSuccess) { "All Deployments Successful" } else { "Deployment Complete (with failures)" }

    $fields = [System.Collections.ArrayList]@()

    if ($Deployed.Count -gt 0) {
        [void]$fields.Add(@{ name = "Deployed ($($Deployed.Count))"; value = ($Deployed -join ", "); inline = [bool]$false })
    }

    if ($Failed.Count -gt 0) {
        [void]$fields.Add(@{ name = "Failed ($($Failed.Count))"; value = ($Failed -join ", "); inline = [bool]$false })
    }

    if ($CustomMessage) {
        [void]$fields.Add(@{ name = "Notes"; value = $CustomMessage; inline = [bool]$false })
    }

    $embed = @{
        title = $title
        color = $color
        fields = $fields.ToArray()
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        footer = @{
            text = "Portfolio Deployment Summary"
        }
    }

    $payload = @{
        embeds = @($embed)
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "application/json" -Body $payload | Out-Null
    }
    catch {
        Write-Warning "Failed to send Discord summary: $($_.Exception.Message)"
    }
}

# Deploy a single frontend
function Deploy-Frontend {
    param([string]$Name)

    $config = $FRONTENDS[$Name]
    if (-not $config) {
        Write-Error "Unknown frontend: $Name"
        return $false
    }

    $path = $config.Path
    $s3Bucket = $config.S3Bucket
    $cfId = $config.CloudFrontId
    $distDir = $config.DistDir

    # Dry run mode - simulate deployment
    if ($DryRun) {
        Write-Header "[DRY RUN] Deploying Frontend: $Name"
        Write-Host "  Path: $path"
        Write-Host "  S3 Bucket: $s3Bucket"
        Write-Host "  CloudFront ID: $cfId"
        $gitInfo = Get-GitInfo -RepoPath $path
        Write-Host "  Git: $gitInfo"
        Write-Success "[DRY RUN] $Name would be deployed"
        Write-Host "  URL: https://$Name.$DOMAIN"

        # Send Discord notification for dry run
        Send-DiscordNotification -ServiceName "$Name (dry-run)" -ServiceType "Frontend" -ServiceUrl "https://$Name.$DOMAIN" -GitInfo $gitInfo -CustomMessage $Message -Success $true

        return $true
    }

    Write-Header "Deploying Frontend: $Name"

    # Check if path exists
    if (-not (Test-Path $path)) {
        Write-Error "Path not found: $path"
        return $false
    }

    Push-Location $path

    try {
        # Build
        if (-not $SkipBuild) {
            Write-Host "Building $Name..."

            # Install dependencies if node_modules doesn't exist
            if (-not (Test-Path "node_modules")) {
                Write-Host "Installing dependencies..."
                npm install
                if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
            }

            # Run build
            Invoke-Expression $config.BuildCmd
            if ($LASTEXITCODE -ne 0) { throw "Build failed" }
            Write-Success "Build completed"
        } else {
            Write-Warning "Skipping build (--SkipBuild)"
        }

        # Upload to S3
        $buildPath = Join-Path $path $distDir
        if (-not (Test-Path $buildPath)) {
            throw "Build directory not found: $buildPath"
        }

        Write-Host "Uploading to S3..."

        # Upload static assets with long cache
        aws s3 sync $buildPath "s3://$s3Bucket" `
            --delete `
            --cache-control "public, max-age=31536000" `
            --exclude "index.html" `
            --exclude "*.json"

        if ($LASTEXITCODE -ne 0) { throw "S3 sync failed" }

        # Upload index.html with no-cache
        aws s3 cp "$buildPath\index.html" "s3://$s3Bucket/index.html" `
            --cache-control "no-cache, no-store, must-revalidate"

        if ($LASTEXITCODE -ne 0) { throw "index.html upload failed" }

        Write-Success "Uploaded to S3"

        # Invalidate CloudFront
        if (-not $SkipInvalidation -and $cfId) {
            Write-Host "Invalidating CloudFront cache..."
            $result = aws cloudfront create-invalidation `
                --distribution-id $cfId `
                --paths "/*" `
                --query 'Invalidation.Id' `
                --output text

            if ($LASTEXITCODE -ne 0) { throw "CloudFront invalidation failed" }
            Write-Success "Cache invalidation created: $result"
        }

        Write-Success "$Name deployed successfully!"
        Write-Host "URL: https://$Name.$DOMAIN"

        # Send Discord notification
        $gitInfo = Get-GitInfo -RepoPath $path
        Send-DiscordNotification -ServiceName $Name -ServiceType "Frontend" -ServiceUrl "https://$Name.$DOMAIN" -GitInfo $gitInfo -CustomMessage $Message -Success $true

        return $true
    }
    catch {
        Write-Error $_.Exception.Message

        # Send failure notification
        $gitInfo = Get-GitInfo -RepoPath $path
        Send-DiscordNotification -ServiceName $Name -ServiceType "Frontend" -ServiceUrl "https://$Name.$DOMAIN" -GitInfo $gitInfo -CustomMessage $Message -Success $false

        return $false
    }
    finally {
        Pop-Location
    }
}

# Deploy a single backend
function Deploy-Backend {
    param([string]$Name)

    $config = $BACKENDS[$Name]
    if (-not $config) {
        Write-Error "Unknown backend: $Name"
        return $false
    }

    $path = $config.Path
    $image = $config.Image
    $container = $config.Container

    # Dry run mode - simulate deployment
    if ($DryRun) {
        Write-Header "[DRY RUN] Deploying Backend: $Name"
        Write-Host "  Path: $path"
        Write-Host "  Docker Image: $image"
        Write-Host "  Container: $container"
        Write-Host "  EC2 Host: $EC2_HOST"
        $gitInfo = Get-GitInfo -RepoPath $path
        Write-Host "  Git: $gitInfo"
        Write-Success "[DRY RUN] $Name would be deployed"

        # Send Discord notification for dry run
        Send-DiscordNotification -ServiceName "$Name (dry-run)" -ServiceType "Backend" -GitInfo $gitInfo -CustomMessage $Message -Success $true

        return $true
    }

    Write-Header "Deploying Backend: $Name"

    # Check if path exists
    if (-not (Test-Path $path)) {
        Write-Error "Path not found: $path"
        return $false
    }

    # Check SSH key
    if (-not (Test-Path $SSH_KEY)) {
        Write-Error "SSH key not found: $SSH_KEY"
        return $false
    }

    try {
        Write-Host "Building Docker image locally..."

        Push-Location $path

        # Build Docker image
        docker build --no-cache -t "${image}:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

        # Save image to tar
        $tarFile = "$env:TEMP\${image}.tar"
        Write-Host "Saving image to $tarFile..."
        docker save -o $tarFile "${image}:latest"
        if ($LASTEXITCODE -ne 0) { throw "Docker save failed" }

        Pop-Location

        # Transfer to EC2
        Write-Host "Transferring image to EC2..."
        scp -i $SSH_KEY -o StrictHostKeyChecking=no $tarFile "${EC2_USER}@${EC2_HOST}:/tmp/"
        if ($LASTEXITCODE -ne 0) { throw "SCP transfer failed" }

        # Load and restart on EC2
        Write-Host "Loading image and restarting container on EC2..."
        # Also copy docker-compose.prod.yml if it changed
        $composeFile = "$PSScriptRoot\..\docker\docker-compose.prod.yml"
        if (Test-Path $composeFile) {
            Write-Host "Syncing docker-compose.prod.yml..."
            scp -i $SSH_KEY -o StrictHostKeyChecking=no $composeFile "${EC2_USER}@${EC2_HOST}:/opt/portfolio/deployment/docker-compose.yml"
        }

        $sshCommands = @"
docker load -i /tmp/${image}.tar && \
rm /tmp/${image}.tar && \
cd /opt/portfolio/deployment && \
docker-compose stop $container && \
docker-compose rm -f $container && \
docker-compose up -d $container
"@

        ssh -i $SSH_KEY -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" $sshCommands
        if ($LASTEXITCODE -ne 0) { throw "SSH deployment failed" }

        # Cleanup local tar
        Remove-Item $tarFile -ErrorAction SilentlyContinue

        Write-Success "$Name deployed successfully!"

        # Send Discord notification
        $gitInfo = Get-GitInfo -RepoPath $path
        Send-DiscordNotification -ServiceName $Name -ServiceType "Backend" -GitInfo $gitInfo -CustomMessage $Message -Success $true

        return $true
    }
    catch {
        Write-Error $_.Exception.Message

        # Send failure notification
        $gitInfo = Get-GitInfo -RepoPath $path
        Send-DiscordNotification -ServiceName $Name -ServiceType "Backend" -GitInfo $gitInfo -CustomMessage $Message -Success $false

        return $false
    }
}

# Main execution
$headerTitle = if ($DryRun) { "Portfolio Deployment Script [DRY RUN]" } else { "Portfolio Deployment Script" }
Write-Header $headerTitle
Write-Host "Service: $Service"
Write-Host "Domain: $DOMAIN"
Write-Host "Region: $AWS_REGION"
if ($DryRun) { Write-ColorOutput 'Yellow' "Mode: DRY RUN (no actual deployment)" }
Write-Host ""

$success = $true
$deployed = @()
$failed = @()

switch ($Service) {
    'all' {
        # Deploy all frontends
        foreach ($name in $FRONTENDS.Keys) {
            if (Deploy-Frontend $name) {
                $deployed += $name
            } else {
                $failed += $name
                $success = $false
            }
        }
        # Deploy all backends
        foreach ($name in $BACKENDS.Keys) {
            if (Deploy-Backend $name) {
                $deployed += $name
            } else {
                $failed += $name
                $success = $false
            }
        }
    }
    'frontends' {
        foreach ($name in $FRONTENDS.Keys) {
            if (Deploy-Frontend $name) {
                $deployed += $name
            } else {
                $failed += $name
                $success = $false
            }
        }
    }
    'backends' {
        foreach ($name in $BACKENDS.Keys) {
            if (Deploy-Backend $name) {
                $deployed += $name
            } else {
                $failed += $name
                $success = $false
            }
        }
    }
    { $_ -in $FRONTENDS.Keys } {
        if (Deploy-Frontend $Service) {
            $deployed += $Service
        } else {
            $failed += $Service
            $success = $false
        }
    }
    { $_ -in $BACKENDS.Keys } {
        if (Deploy-Backend $Service) {
            $deployed += $Service
        } else {
            $failed += $Service
            $success = $false
        }
    }
}

# Summary
Write-Header "Deployment Summary"

if ($deployed.Count -gt 0) {
    Write-Success "Deployed: $($deployed -join ', ')"
}

if ($failed.Count -gt 0) {
    Write-Error "Failed: $($failed -join ', ')"
}

Write-Host ""
Write-Host "URLs:"
Write-Host "  Portfolio: https://portfolio.$DOMAIN"
Write-Host "  Photos:    https://photos.$DOMAIN"
Write-Host "  Security:  https://security.$DOMAIN"
Write-Host "  Shipping:  https://shipping.$DOMAIN"
Write-Host "  API:       https://api.$DOMAIN"
Write-Host ""

# Send deployment summary to Discord (only if multiple services were targeted)
if ($deployed.Count + $failed.Count -gt 1) {
    Send-DiscordSummary -Deployed $deployed -Failed $failed -CustomMessage $Message
}

if ($success) {
    Write-Success "All deployments completed successfully!"
    exit 0
} else {
    Write-Error "Some deployments failed. Check the output above."
    exit 1
}
