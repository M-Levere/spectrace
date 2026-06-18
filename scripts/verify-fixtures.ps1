#!/usr/bin/env pwsh
# verify-fixtures.ps1 — Smoke-checks that all expected fixture files exist.
# Run from the repo root:  pwsh scripts/verify-fixtures.ps1
# Exit 0 = all files present.  Exit 1 = missing files (lists them).

param(
    [string]$FixtureRoot = (Join-Path $PSScriptRoot '../docs/examples')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$missing = @()

function Expect-File([string]$Rel) {
    $full = Join-Path $FixtureRoot $Rel
    if (-not (Test-Path $full)) {
        $script:missing += $Rel
        Write-Host "  MISSING  $Rel" -ForegroundColor Red
    } else {
        Write-Host "  OK       $Rel" -ForegroundColor Green
    }
}

Write-Host "`n=== playwright-bdd bundles ==="
$pwScenarios = @('passing','selector-failure','timeout','assertion','flaky')
$pwFeatures  = @('login',  'checkout',        'search', 'dashboard','payment')
for ($i = 0; $i -lt $pwScenarios.Count; $i++) {
    $s = $pwScenarios[$i]; $f = $pwFeatures[$i]
    Expect-File "playwright-bdd/$s/report.json"
    Expect-File "playwright-bdd/$s/trace.zip"
    Expect-File "playwright-bdd/$s/features/$f.feature"
    Expect-File "playwright-bdd/$s/steps/$f.steps.ts"
    # screenshot — name varies (on-failure vs baseline)
    $shotPass    = "playwright-bdd/$s/screenshot.png"
    $shotFailure = "playwright-bdd/$s/screenshot-on-failure.png"
    if (-not ((Test-Path (Join-Path $FixtureRoot $shotPass)) -or (Test-Path (Join-Path $FixtureRoot $shotFailure)))) {
        $missing += "$shotPass or $shotFailure"
        Write-Host "  MISSING  screenshot for $s" -ForegroundColor Red
    } else {
        Write-Host "  OK       screenshot for $s" -ForegroundColor Green
    }
}

Write-Host "`n=== jest bundles ==="
foreach ($s in @('passing','failing-assertion','failing-timeout','flaky')) {
    Expect-File "jest/$s/results.json"
}

Write-Host "`n=== trx bundles ==="
foreach ($s in @('passing','failing-assertion','failing-timeout','flaky')) {
    Expect-File "trx/$s/results.trx"
}

Write-Host "`n=== junit bundles ==="
foreach ($s in @('passing','failing-assertion','failing-timeout','flaky')) {
    Expect-File "junit/$s/results.xml"
}

Write-Host ''
if ($missing.Count -gt 0) {
    Write-Host "$($missing.Count) missing file(s). Run scripts/generate-fixtures.ps1 to regenerate." -ForegroundColor Red
    exit 1
}

Write-Host "All fixture files present ($((Get-ChildItem $FixtureRoot -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' }).Count) files)." -ForegroundColor Cyan
exit 0
