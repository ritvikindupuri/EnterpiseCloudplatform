# Package Lambda Functions for Deployment

Write-Host "Packaging Lambda functions..." -ForegroundColor Cyan

# Create lambda-packages directory
New-Item -ItemType Directory -Force -Path "lambda-packages" | Out-Null

# Package ML Detector Lambda
Write-Host "Packaging ML detector..." -ForegroundColor Yellow
Set-Location lambda-functions
Compress-Archive -Path ml_detector.py -DestinationPath ../lambda-packages/ml-detector.zip -Force
Set-Location ..

Write-Host "Lambda functions packaged successfully" -ForegroundColor Green
Write-Host "  - lambda-packages/ml-detector.zip" -ForegroundColor White
