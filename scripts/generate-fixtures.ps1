#!/usr/bin/env pwsh
# generate-fixtures.ps1 -Creates all SpecTrace example fixture bundles.
# Run from the repo root:  pwsh scripts/generate-fixtures.ps1
# Output:  docs/examples/{playwright-bdd,jest,trx,junit}/<scenario>/

param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '../docs/examples'),
    [string]$DemoRoot   = (Join-Path $PSScriptRoot '../demo')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Minimal 1x1 white PNG (valid screenshot placeholder)
$script:PngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

function New-PlaceholderPng([string]$Path) {
    [IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($script:PngBase64))
}

function New-TraceZip([string]$Path, [string]$ScenarioName) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "spectrace-trace-$([IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        @{ version = 3; scenario = $ScenarioName; actions = @() } |
            ConvertTo-Json | Set-Content "$tmpDir/trace.trace" -Encoding UTF8
        '{"version":3,"log":[]}' | Set-Content "$tmpDir/trace.network" -Encoding UTF8
        if (Test-Path $Path) { Remove-Item $Path -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $Path)
    } finally {
        Remove-Item -Recurse -Force $tmpDir
    }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Copy-DemoFile([string]$Src, [string]$Dst) {
    Ensure-Dir (Split-Path $Dst)
    Copy-Item $Src $Dst -Force
}

# ---------------------------------------------------------------------------
# Playwright-bdd JSON report builder
# ---------------------------------------------------------------------------

function Build-PwStep {
    param(
        [string]$Title,
        [string]$Category = 'test.step',
        [string]$StartTime,
        [int]$DurationMs,
        [object]$Error = $null,
        [object[]]$InnerSteps = @()
    )
    [ordered]@{
        title     = $Title
        category  = $Category
        startTime = $StartTime
        duration  = $DurationMs
        steps     = $InnerSteps
        error     = $Error
    }
}

function Build-PwError([string]$Message, [string]$Stack) {
    [ordered]@{
        message = $Message
        value   = $Stack
    }
}

function New-PlaywrightBddReport {
    param(
        [string]$FeatureFile,
        [string]$FeatureTitle,
        [string]$ScenarioTitle,
        [string]$ProjectRoot,
        [string]$StartIso,
        [int]$TotalMs,
        [string]$TestStatus,   # passed | failed | flaky (flaky = failed first + passed retry)
        [object[]]$Steps,
        [object[]]$Errors = @(),
        [object[]]$Attachments = @(),
        [int]$Retries = 0,
        [int]$RetryIndex = 0
    )

    $expectedStatus  = if ($TestStatus -eq 'passed') { 'passed' } else { 'failed' }
    $overallStatus   = if ($TestStatus -eq 'passed') { 'expected' } else { 'unexpected' }
    $resultStatus    = if ($TestStatus -eq 'passed') { 'passed' } else { 'failed' }

    $result = [ordered]@{
        workerIndex   = 0
        parallelIndex = 0
        status        = $resultStatus
        duration      = $TotalMs
        errors        = $Errors
        stdout        = @()
        stderr        = @()
        retry         = $RetryIndex
        startTime     = $StartIso
        attachments   = $Attachments
        steps         = $Steps
    }

    $spec = [ordered]@{
        title = $ScenarioTitle
        ok    = ($TestStatus -eq 'passed')
        tags  = @()
        tests = @(
            [ordered]@{
                timeout        = 30000
                annotations    = @()
                expectedStatus = $expectedStatus
                projectId      = 'chromium'
                projectName    = 'chromium'
                results        = @($result)
                status         = $overallStatus
            }
        )
        id   = [guid]::NewGuid().ToString('N').Substring(0, 12)
        file = $FeatureFile
        line = 7
    }

    $expectedCount  = if ($TestStatus -eq 'passed') { 1 } else { 0 }
    $unexpectedCount = if ($TestStatus -eq 'passed') { 0 } else { 1 }

    [ordered]@{
        config = [ordered]@{
            configFile      = "$ProjectRoot/playwright.config.ts"
            rootDir         = $ProjectRoot
            forbidOnly      = $false
            fullyParallel   = $false
            globalSetup     = $null
            globalTeardown  = $null
            globalTimeout   = 0
            grep            = '(?:)'
            grepInvert      = $null
            maxFailures     = 0
            metadata        = [ordered]@{}
            preserveOutput  = 'always'
            reporter        = @(@('json', [ordered]@{ outputFile = 'test-results/report.json' }))
            reportSlowTests = [ordered]@{ max = 5; threshold = 15000 }
            quiet           = $false
            projects        = @(
                [ordered]@{
                    outputDir  = "$ProjectRoot/test-results"
                    repeatEach = 1
                    retries    = $Retries
                    id         = 'chromium'
                    name       = 'chromium'
                    testDir    = "$ProjectRoot/.features-gen"
                    testIgnore = @()
                    testMatch  = @('**/*.spec.ts')
                    timeout    = 30000
                }
            )
            version = '1.48.0'
            workers = 1
        }
        suites = @(
            [ordered]@{
                title  = "$($FeatureFile -replace '\.feature$','').feature.spec.ts"
                file   = $FeatureFile
                column = 0
                line   = 0
                specs  = @()
                suites = @(
                    [ordered]@{
                        title  = $FeatureTitle
                        file   = $FeatureFile
                        line   = 1
                        column = 0
                        specs  = @()
                        suites = @(
                            [ordered]@{
                                title  = $ScenarioTitle
                                file   = $FeatureFile
                                line   = 7
                                column = 0
                                specs  = @($spec)
                            }
                        )
                    }
                )
            }
        )
        errors = @()
        stats  = [ordered]@{
            startTime   = $StartIso
            duration    = $TotalMs
            expected    = $expectedCount
            skipped     = 0
            unexpected  = $unexpectedCount
            flaky       = 0
        }
    }
}

# ---------------------------------------------------------------------------
# Playwright-bdd bundles
# ---------------------------------------------------------------------------

function New-PwBundle {
    param(
        [string]$Scenario,      # passing | selector-failure | timeout | assertion | flaky
        [string]$FeatureName,   # login | checkout | search | dashboard | payment
        [string]$FeatureTitle,
        [string]$ScenarioTitle,
        [string]$StartIso,
        [int]$TotalMs,
        [string]$TestStatus,
        [object[]]$Steps,
        [object[]]$Errors = @()
    )

    $dir = Join-Path $OutputRoot "playwright-bdd/$Scenario"
    Ensure-Dir "$dir/features"
    Ensure-Dir "$dir/steps"

    # Copy feature + step files from demo
    $featureSrc = Join-Path $DemoRoot "playwright-bdd/features/$FeatureName.feature"
    $stepSrc    = Join-Path $DemoRoot "playwright-bdd/steps/$FeatureName.steps.ts"
    if (Test-Path $featureSrc) { Copy-Item $featureSrc "$dir/features/$FeatureName.feature" -Force }
    if (Test-Path $stepSrc)    { Copy-Item $stepSrc    "$dir/steps/$FeatureName.steps.ts"   -Force }

    # Screenshot
    $screenshotName = if ($TestStatus -ne 'passed') { 'screenshot-on-failure.png' } else { 'screenshot.png' }
    New-PlaceholderPng (Join-Path $dir $screenshotName)

    # Trace
    New-TraceZip (Join-Path $dir 'trace.zip') $ScenarioTitle

    # Attachment list for the report
    $attachments = @(
        [ordered]@{ name = 'trace'; contentType = 'application/zip'; path = "test-results/$Scenario-chromium/trace.zip" }
    )
    if ($TestStatus -ne 'passed') {
        $attachments += [ordered]@{ name = 'screenshot'; contentType = 'image/png'; path = "test-results/$Scenario-chromium/$screenshotName" }
    }

    $projectRoot = (Join-Path $DemoRoot 'playwright-bdd') -replace '\\','/'
    $report = New-PlaywrightBddReport `
        -FeatureFile   "features/$FeatureName.feature" `
        -FeatureTitle  $FeatureTitle `
        -ScenarioTitle $ScenarioTitle `
        -ProjectRoot   $projectRoot `
        -StartIso      $StartIso `
        -TotalMs       $TotalMs `
        -TestStatus    $TestStatus `
        -Steps         $Steps `
        -Errors        $Errors `
        -Attachments   $attachments

    $report | ConvertTo-Json -Depth 20 -Compress:$false |
        Set-Content (Join-Path $dir 'report.json') -Encoding UTF8

    Write-Host "  [pw-bdd] $Scenario -OK"
}

# ---------------------------------------------------------------------------
# Shared step factory helpers
# ---------------------------------------------------------------------------

function Make-PwApiStep([string]$Api, [string]$Start, [int]$Ms, [object]$Err = $null) {
    Build-PwStep -Title $Api -Category 'pw:api' -StartTime $Start -DurationMs $Ms -Error $Err
}

function T([string]$Base, [int]$OffsetMs) {
    # Add milliseconds to an ISO timestamp string
    [datetime]::Parse($Base).AddMilliseconds($OffsetMs).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

# ---------------------------------------------------------------------------
# 1. PASSING -login
# ---------------------------------------------------------------------------

$t0 = '2024-11-15T10:00:00.000Z'
$passingSteps = @(
    Build-PwStep 'Before Hooks'                        'hook'      $t0           523 $null @()
    Build-PwStep 'Given I am on the login page'        'test.step' (T $t0 523)  312 $null @(
        Make-PwApiStep "page.goto('http://localhost:3000/login')" (T $t0 523) 300
    )
    Build-PwStep 'When I enter username "test@example.com"' 'test.step' (T $t0 835) 48 $null @(
        Make-PwApiStep "locator.fill('test@example.com')" (T $t0 835) 45
    )
    Build-PwStep 'And I enter password "SecurePass123"' 'test.step' (T $t0 883) 42 $null @(
        Make-PwApiStep "locator.fill('SecurePass123')" (T $t0 883) 40
    )
    Build-PwStep 'And I click the login button'        'test.step' (T $t0 925) 634 $null @(
        Make-PwApiStep "locator.click()"               (T $t0 925) 630
    )
    Build-PwStep 'Then I should be redirected to the dashboard' 'test.step' (T $t0 1559) 487 $null @(
        Make-PwApiStep "expect(page).toHaveURL('/dashboard')" (T $t0 1559) 485
    )
    Build-PwStep 'And I should see the welcome message "Welcome back, Test User"' 'test.step' (T $t0 2046) 245 $null @(
        Make-PwApiStep "expect(locator).toContainText('Welcome back, Test User')" (T $t0 2046) 243
    )
    Build-PwStep 'After Hooks'                         'hook'      (T $t0 2291) 50 $null @()
)

New-PwBundle `
    -Scenario      'passing' `
    -FeatureName   'login' `
    -FeatureTitle  'User Login' `
    -ScenarioTitle 'Successful login with valid credentials' `
    -StartIso      $t0 `
    -TotalMs       2341 `
    -TestStatus    'passed' `
    -Steps         $passingSteps

# ---------------------------------------------------------------------------
# 2. SELECTOR-FAILURE -checkout
# ---------------------------------------------------------------------------

$t1 = '2024-11-15T10:05:00.000Z'
$selectorErrMsg = "page.locator('.checkout-btn.primary').click: Timeout 30000ms exceeded.`nCall log:`n  - waiting for locator('.checkout-btn.primary')`n  -   selector resolved to 0 elements"
$selectorErrVal = "TimeoutError: page.locator('.checkout-btn.primary').click: Timeout 30000ms exceeded.`nCall log:`n  - waiting for locator('.checkout-btn.primary')`n  -   selector resolved to 0 elements`n    at steps/checkout.steps.ts:20:42`n    at Test.<anonymous> (.features-gen/checkout.feature.spec.ts:31:5)"
$selectorErr = Build-PwError $selectorErrMsg $selectorErrVal

$selectorSteps = @(
    Build-PwStep 'Before Hooks'                         'hook'      $t1          634 $null @()
    Build-PwStep 'Given I am logged in and have items in my shopping cart' 'test.step' (T $t1 634) 1243 $null @(
        Make-PwApiStep "page.goto('http://localhost:3000/cart')" (T $t1 634) 1240
    )
    Build-PwStep 'When I proceed to checkout'           'test.step' (T $t1 1877) 892 $null @(
        Make-PwApiStep "locator.click()" (T $t1 1877) 320
        Make-PwApiStep "expect(page).toHaveURL('/checkout')" (T $t1 2197) 572
    )
    Build-PwStep 'And I enter my shipping address'      'test.step' (T $t1 2769) 156 $null @(
        Make-PwApiStep "locator.fill('123 Main St')" (T $t1 2769) 52
        Make-PwApiStep "locator.fill('Anytown')"     (T $t1 2821) 50
        Make-PwApiStep "locator.fill('12345')"       (T $t1 2871) 54
    )
    Build-PwStep 'And I click the "Place Order" button' 'test.step' (T $t1 2925) 30045 $selectorErr @(
        Make-PwApiStep "page.locator('.checkout-btn.primary').click()" (T $t1 2925) 30045 $selectorErr
    )
    Build-PwStep 'After Hooks'                          'hook'      (T $t1 32970) 120 $null @(
        Make-PwApiStep "page.screenshot()" (T $t1 32970) 115
    )
)

New-PwBundle `
    -Scenario      'selector-failure' `
    -FeatureName   'checkout' `
    -FeatureTitle  'Shopping Cart Checkout' `
    -ScenarioTitle 'Complete checkout with valid payment details' `
    -StartIso      $t1 `
    -TotalMs       33090 `
    -TestStatus    'failed' `
    -Steps         $selectorSteps `
    -Errors        @($selectorErr)

# ---------------------------------------------------------------------------
# 3. TIMEOUT -search
# ---------------------------------------------------------------------------

$t2 = '2024-11-15T10:10:00.000Z'
$timeoutMsg = 'page.locator(''[data-testid="search-results"]'').waitFor: Timeout 5000ms exceeded.'
$timeoutVal = "TimeoutError: page.locator('[data-testid=""search-results""]').waitFor: Timeout 5000ms exceeded.`n    at steps/search.steps.ts:14:58`n    at Test.<anonymous> (.features-gen/search.feature.spec.ts:27:5)"
$timeoutErr = Build-PwError $timeoutMsg $timeoutVal

$timeoutSteps = @(
    Build-PwStep 'Before Hooks'                         'hook'      $t2          401 $null @()
    Build-PwStep 'Given I am on the product catalog page' 'test.step' (T $t2 401) 823 $null @(
        Make-PwApiStep "page.goto('http://localhost:3000/products')" (T $t2 401) 820
    )
    Build-PwStep 'When I enter "wireless headphones" in the search box' 'test.step' (T $t2 1224) 65 $null @(
        Make-PwApiStep "locator.fill('wireless headphones')" (T $t2 1224) 62
    )
    Build-PwStep 'And I submit the search query'        'test.step' (T $t2 1289) 5012 $timeoutErr @(
        Make-PwApiStep "page.keyboard.press('Enter')"  (T $t2 1289) 10
        Make-PwApiStep "locator.waitFor({state:'visible',timeout:5000})" (T $t2 1299) 5002 $timeoutErr
    )
    Build-PwStep 'After Hooks'                          'hook'      (T $t2 6301) 134 $null @(
        Make-PwApiStep "page.screenshot()" (T $t2 6301) 130
    )
)

New-PwBundle `
    -Scenario      'timeout' `
    -FeatureName   'search' `
    -FeatureTitle  'Product Search' `
    -ScenarioTitle 'Search for products by keyword' `
    -StartIso      $t2 `
    -TotalMs       6435 `
    -TestStatus    'failed' `
    -Steps         $timeoutSteps `
    -Errors        @($timeoutErr)

# ---------------------------------------------------------------------------
# 4. ASSERTION -dashboard
# ---------------------------------------------------------------------------

$t3 = '2024-11-15T10:15:00.000Z'
$assertMsg = "expect(received).toBeGreaterThan(expected)`n`nExpected: > 100`nReceived:   0`n`nThe daily active users metric returned 0. The analytics pipeline may not have processed data for the selected range yet."
$assertVal = "Error: expect(received).toBeGreaterThan(expected)`n`nExpected: > 100`nReceived:   0`n    at steps/dashboard.steps.ts:24:18`n    at Test.<anonymous> (.features-gen/dashboard.feature.spec.ts:41:5)"
$assertErr = Build-PwError $assertMsg $assertVal

$assertSteps = @(
    Build-PwStep 'Before Hooks'                         'hook'      $t3          702 $null @()
    Build-PwStep 'Given I am logged in as an admin user' 'test.step' (T $t3 702) 1834 $null @(
        Make-PwApiStep "page.goto('http://localhost:3000/login')" (T $t3 702)  812
        Make-PwApiStep "locator.fill('admin@example.com')"        (T $t3 1514) 44
        Make-PwApiStep "locator.fill('AdminPass456')"             (T $t3 1558) 41
        Make-PwApiStep "locator.click()"                          (T $t3 1599) 610
        Make-PwApiStep "expect(page).toHaveURL('/dashboard')"     (T $t3 2209) 327
    )
    Build-PwStep 'And I navigate to the analytics dashboard' 'test.step' (T $t3 2536) 934 $null @(
        Make-PwApiStep "locator.click()"                          (T $t3 2536) 230
        Make-PwApiStep "expect(page).toHaveURL('/analytics')"     (T $t3 2766) 704
    )
    Build-PwStep 'When I select the date range "Last 7 days"' 'test.step' (T $t3 3470) 623 $null @(
        Make-PwApiStep "locator.click()"   (T $t3 3470) 210
        Make-PwApiStep "locator.click()"   (T $t3 3680) 201
        Make-PwApiStep "locator.click()"   (T $t3 3881) 212
    )
    Build-PwStep 'Then the daily active users count should be greater than 100' 'test.step' (T $t3 4093) 45 $assertErr @(
        Make-PwApiStep "locator.innerText()" (T $t3 4093) 12 $null
    )
    Build-PwStep 'After Hooks'                          'hook'      (T $t3 4138) 124 $null @(
        Make-PwApiStep "page.screenshot()" (T $t3 4138) 120
    )
)

New-PwBundle `
    -Scenario      'assertion' `
    -FeatureName   'dashboard' `
    -FeatureTitle  'Analytics Dashboard' `
    -ScenarioTitle 'View daily active users metric' `
    -StartIso      $t3 `
    -TotalMs       4262 `
    -TestStatus    'failed' `
    -Steps         $assertSteps `
    -Errors        @($assertErr)

# ---------------------------------------------------------------------------
# 5. FLAKY -payment (failed first attempt, passed on retry 1)
# ---------------------------------------------------------------------------

$t4 = '2024-11-15T10:20:00.000Z'
$flakyMsg = "expect(locator).toBeVisible()`n`nLocator: locator('[data-testid=""payment-success-modal""]')`nExpected: visible`nReceived: hidden`n`nCall log:`n  - expect.toBeVisible with timeout 2000ms`n  - waiting for locator('[data-testid=""payment-success-modal""]')"
$flakyVal  = "Error: expect(locator).toBeVisible()`n`nLocator: locator('[data-testid=""payment-success-modal""]')`n    at steps/payment.steps.ts:18:74`n    at Test.<anonymous> (.features-gen/payment.feature.spec.ts:36:5)"
$flakyErr  = Build-PwError $flakyMsg $flakyVal

$flakyDir = Join-Path $OutputRoot 'playwright-bdd/flaky'
Ensure-Dir "$flakyDir/features"
Ensure-Dir "$flakyDir/steps"

$featureSrc = Join-Path $DemoRoot 'playwright-bdd/features/payment.feature'
$stepSrc    = Join-Path $DemoRoot 'playwright-bdd/steps/payment.steps.ts'
if (Test-Path $featureSrc) { Copy-Item $featureSrc "$flakyDir/features/payment.feature" -Force }
if (Test-Path $stepSrc)    { Copy-Item $stepSrc    "$flakyDir/steps/payment.steps.ts"   -Force }

New-PlaceholderPng (Join-Path $flakyDir 'screenshot-on-failure.png')
New-TraceZip (Join-Path $flakyDir 'trace.zip') 'Process payment with credit card'

$buildPaymentSteps = {
    param([bool]$Passing, [string]$Base)
    $result = @(
        (Build-PwStep 'Before Hooks' 'hook' $Base 312 $null @())
        (Build-PwStep 'Given I am on the payment page with a pending order' 'test.step' (T $Base 312) 1102 $null @(
            Make-PwApiStep "page.goto('http://localhost:3000/payment?orderId=DEMO-12345')" (T $Base 312) 1099
        ))
        (Build-PwStep 'When I enter valid credit card details' 'test.step' (T $Base 1414) 182 $null @(
            Make-PwApiStep "locator.fill('4111111111111111')" (T $Base 1414) 45
            Make-PwApiStep "locator.fill('12/26')"           (T $Base 1459) 42
            Make-PwApiStep "locator.fill('123')"             (T $Base 1501) 41
            Make-PwApiStep "locator.fill('Test User')"       (T $Base 1542) 54
        ))
        (Build-PwStep 'And I submit the payment form' 'test.step' (T $Base 1596) 234 $null @(
            Make-PwApiStep "locator.click()" (T $Base 1596) 231
        ))
    )
    if ($Passing) {
        $result += Build-PwStep 'Then the payment should be processed successfully' 'test.step' (T $Base 1830) 312 $null @(
            Make-PwApiStep "expect(locator).toBeVisible({timeout:2000})" (T $Base 1830) 310
        )
        $result += Build-PwStep 'And I should see the payment confirmation with an order number' 'test.step' (T $Base 2142) 145 $null @(
            Make-PwApiStep "expect(locator).toBeVisible()" (T $Base 2142) 143
        )
        $result += Build-PwStep 'After Hooks' 'hook' (T $Base 2287) 48 $null @()
    } else {
        $result += Build-PwStep 'Then the payment should be processed successfully' 'test.step' (T $Base 1830) 2012 $flakyErr @(
            Make-PwApiStep "expect(locator).toBeVisible({timeout:2000})" (T $Base 1830) 2010 $flakyErr
        )
        $result += Build-PwStep 'After Hooks' 'hook' (T $Base 3842) 112 $null @(
            Make-PwApiStep "page.screenshot()" (T $Base 3842) 108
        )
    }
    $result
}

$failedSteps  = & $buildPaymentSteps $false $t4
$retryBase    = '2024-11-15T10:20:05.000Z'
$passedSteps  = & $buildPaymentSteps $true  $retryBase

$projectRoot = (Join-Path $DemoRoot 'playwright-bdd') -replace '\\','/'

$flakyReport = [ordered]@{
    config = [ordered]@{
        configFile      = "$projectRoot/playwright.config.ts"
        rootDir         = $projectRoot
        forbidOnly      = $false
        fullyParallel   = $false
        globalSetup     = $null
        globalTeardown  = $null
        globalTimeout   = 0
        grep            = '(?:)'
        grepInvert      = $null
        maxFailures     = 0
        metadata        = [ordered]@{}
        preserveOutput  = 'always'
        reporter        = @(@('json', [ordered]@{ outputFile = 'test-results/report.json' }))
        reportSlowTests = [ordered]@{ max = 5; threshold = 15000 }
        quiet           = $false
        projects        = @([ordered]@{
            outputDir  = "$projectRoot/test-results"
            repeatEach = 1
            retries    = 2
            id         = 'chromium'
            name       = 'chromium'
            testDir    = "$projectRoot/.features-gen"
            testIgnore = @()
            testMatch  = @('**/*.spec.ts')
            timeout    = 30000
        })
        version = '1.48.0'
        workers = 1
    }
    suites = @([ordered]@{
        title  = 'payment.feature.spec.ts'
        file   = 'features/payment.feature'
        column = 0
        line   = 0
        specs  = @()
        suites = @([ordered]@{
            title  = 'Payment Processing'
            file   = 'features/payment.feature'
            line   = 1
            column = 0
            specs  = @()
            suites = @([ordered]@{
                title  = 'Process payment with credit card'
                file   = 'features/payment.feature'
                line   = 7
                column = 0
                specs  = @([ordered]@{
                    title = 'Process payment with credit card'
                    ok    = $true
                    tags  = @()
                    tests = @([ordered]@{
                        timeout        = 30000
                        annotations    = @()
                        expectedStatus = 'passed'
                        projectId      = 'chromium'
                        projectName    = 'chromium'
                        results        = @(
                            [ordered]@{
                                workerIndex   = 0
                                parallelIndex = 0
                                status        = 'failed'
                                duration      = 3954
                                errors        = @($flakyErr)
                                stdout        = @()
                                stderr        = @()
                                retry         = 0
                                startTime     = $t4
                                attachments   = @(
                                    [ordered]@{ name = 'trace';      contentType = 'application/zip'; path = 'test-results/flaky-chromium/trace.zip' }
                                    [ordered]@{ name = 'screenshot'; contentType = 'image/png';       path = 'test-results/flaky-chromium/screenshot-on-failure.png' }
                                )
                                steps         = $failedSteps
                            }
                            [ordered]@{
                                workerIndex   = 0
                                parallelIndex = 0
                                status        = 'passed'
                                duration      = 2335
                                errors        = @()
                                stdout        = @()
                                stderr        = @()
                                retry         = 1
                                startTime     = $retryBase
                                attachments   = @(
                                    [ordered]@{ name = 'trace'; contentType = 'application/zip'; path = 'test-results/flaky-chromium-retry1/trace.zip' }
                                )
                                steps         = $passedSteps
                            }
                        )
                        status = 'flaky'
                    })
                    id   = [guid]::NewGuid().ToString('N').Substring(0, 12)
                    file = 'features/payment.feature'
                    line = 7
                })
            })
        })
    })
    errors = @()
    stats  = [ordered]@{
        startTime   = $t4
        duration    = 6289
        expected    = 0
        skipped     = 0
        unexpected  = 0
        flaky       = 1
    }
}

$flakyReport | ConvertTo-Json -Depth 20 |
    Set-Content (Join-Path $flakyDir 'report.json') -Encoding UTF8

Write-Host '  [pw-bdd] flaky -OK'

# ---------------------------------------------------------------------------
# Jest fixtures
# ---------------------------------------------------------------------------

function New-JestBundle([string]$Scenario) {
    $dir = Join-Path $OutputRoot "jest/$Scenario"
    Ensure-Dir $dir

    $startMs = 1731657600000  # 2024-11-15T10:00:00Z in epoch ms

    switch ($Scenario) {
        'passing' {
            $suiteStatus = 'passed'
            $total = 3; $pass = 3; $fail = 0
            $assertions = @(
                [ordered]@{
                    ancestorTitles    = @('User Login', 'Successful login with valid credentials')
                    duration          = 45
                    failureMessages   = @()
                    fullName          = 'User Login Successful login with valid credentials returns a session token for valid credentials'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 6 }
                    numPassingAsserts = 2
                    status            = 'passed'
                    title             = 'returns a session token for valid credentials'
                }
                [ordered]@{
                    ancestorTitles    = @('User Login', 'Successful login with valid credentials')
                    duration          = 12
                    failureMessages   = @()
                    fullName          = 'User Login Successful login with valid credentials returns the correct welcome message'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 12 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'returns the correct welcome message'
                }
                [ordered]@{
                    ancestorTitles    = @('User Login', 'Successful login with valid credentials')
                    duration          = 8
                    failureMessages   = @()
                    fullName          = 'User Login Successful login with valid credentials sets the correct session expiry'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 18 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'sets the correct session expiry'
                }
            )
            $testFile = '__tests__/login.test.ts'
            $message  = ''
        }
        'failing-assertion' {
            $suiteStatus = 'failed'
            $total = 3; $pass = 2; $fail = 1
            $assertions = @(
                [ordered]@{
                    ancestorTitles    = @('Shopping Cart Checkout', 'Order total calculation')
                    duration          = 18
                    failureMessages   = @()
                    fullName          = 'Shopping Cart Checkout Order total calculation calculates total correctly for multiple items'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 6 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'calculates total correctly for multiple items'
                }
                [ordered]@{
                    ancestorTitles    = @('Shopping Cart Checkout', 'Order total calculation')
                    duration          = 12
                    failureDetails    = @([ordered]@{
                        matcherResult = [ordered]@{
                            actual   = 90.00000000001
                            expected = 90
                            message  = "Expected: 90`nReceived: 90.00000000001"
                            name     = 'toBe'
                            pass     = $false
                        }
                    })
                    failureMessages   = @("Error: expect(received).toBe(expected) // Object.is equality`n`nExpected: 90`nReceived: 90.00000000001`n    at Object.<anonymous> (demo/jest/__tests__/checkout.test.ts:15:32)")
                    fullName          = 'Shopping Cart Checkout Order total calculation applies 10% discount correctly'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 12 }
                    numPassingAsserts = 0
                    status            = 'failed'
                    title             = 'applies 10% discount correctly'
                }
                [ordered]@{
                    ancestorTitles    = @('Shopping Cart Checkout', 'Order total calculation')
                    duration          = 7
                    failureMessages   = @()
                    fullName          = 'Shopping Cart Checkout Order total calculation returns zero for empty cart'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 20 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'returns zero for empty cart'
                }
            )
            $testFile = '__tests__/checkout.test.ts'
            $message  = "  * Shopping Cart Checkout > Order total calculation > applies 10% discount correctly`n`n    expect(received).toBe(expected)`n`n    Expected: 90`n    Received: 90.00000000001`n`n      13 |     it('applies 10% discount correctly', () => {`n      14 |       const discounted = applyDiscount(subtotal, 0.10);`n    > 15 |       expect(discounted).toBe(90.00);`n         |                         ^`n      16 |     });`n`n      at Object.<anonymous> (demo/jest/__tests__/checkout.test.ts:15:25)"
        }
        'failing-timeout' {
            $suiteStatus = 'failed'
            $total = 3; $pass = 2; $fail = 1
            $assertions = @(
                [ordered]@{
                    ancestorTitles    = @('Product Search', 'Search by keyword')
                    duration          = 32
                    failureMessages   = @()
                    fullName          = 'Product Search Search by keyword returns results for a known keyword'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 6 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'returns results for a known keyword'
                }
                [ordered]@{
                    ancestorTitles    = @('Product Search', 'Search by keyword')
                    duration          = 9
                    failureMessages   = @()
                    fullName          = 'Product Search Search by keyword returns empty array for unknown keyword'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 12 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'returns empty array for unknown keyword'
                }
                [ordered]@{
                    ancestorTitles    = @('Product Search', 'Search by keyword')
                    duration          = 5001
                    failureMessages   = @("Exceeded timeout of 5000ms for a test.`nAdd a timeout value to this test to increase the timeout, if this is a long-running test. See https://jestjs.io/docs/api#testname-fn-timeout.`n    at demo/jest/__tests__/search.test.ts:19:3")
                    fullName          = 'Product Search Search by keyword each result has a name and price'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 19 }
                    numPassingAsserts = 0
                    status            = 'failed'
                    title             = 'each result has a name and price'
                }
            )
            $testFile = '__tests__/search.test.ts'
            $message  = "  * Product Search > Search by keyword > each result has a name and price`n`n    Exceeded timeout of 5000ms for a test."
        }
        'flaky' {
            $suiteStatus = 'failed'
            $total = 3; $pass = 2; $fail = 1
            $assertions = @(
                [ordered]@{
                    ancestorTitles    = @('Payment Processing', 'Credit card payment')
                    duration          = 28
                    failureMessages   = @()
                    fullName          = 'Payment Processing Credit card payment returns a confirmation number for valid payment details'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 6 }
                    numPassingAsserts = 2
                    status            = 'passed'
                    title             = 'returns a confirmation number for valid payment details'
                }
                [ordered]@{
                    ancestorTitles    = @('Payment Processing', 'Credit card payment')
                    duration          = 423
                    failureMessages   = @("Error: expect(received).toBe(expected)`n`nExpected: `"settled`"`nReceived: `"unknown`"`n    at Object.<anonymous> (demo/jest/__tests__/payment.test.ts:20:22)`n`nNote: This test is known to be flaky - the payment gateway propagates status after a random delay.")
                    fullName          = 'Payment Processing Credit card payment payment status is queryable by confirmation number'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 13 }
                    numPassingAsserts = 0
                    status            = 'failed'
                    title             = 'payment status is queryable by confirmation number'
                }
                [ordered]@{
                    ancestorTitles    = @('Payment Processing', 'Credit card payment')
                    duration          = 15
                    failureMessages   = @()
                    fullName          = 'Payment Processing Credit card payment rejects expired card'
                    invocations       = 1
                    location          = [ordered]@{ column = 7; line = 24 }
                    numPassingAsserts = 1
                    status            = 'passed'
                    title             = 'rejects expired card'
                }
            )
            $testFile = '__tests__/payment.test.ts'
            $message  = "  * Payment Processing > Credit card payment > payment status is queryable by confirmation number`n`n    expect(received).toBe(expected)`n`n    Expected: `"settled`"`n    Received: `"unknown`""
        }
    }

    $numFail = $fail  # avoids scoping issue

    $report = [ordered]@{
        numFailedTestSuites    = if ($suiteStatus -eq 'failed') { 1 } else { 0 }
        numFailedTests         = $numFail
        numPassedTestSuites    = if ($suiteStatus -eq 'passed') { 1 } else { 0 }
        numPassedTests         = $pass
        numPendingTestSuites   = 0
        numPendingTests        = 0
        numRuntimeErrorTestSuites = 0
        numTodoTests           = 0
        numTotalTestSuites     = 1
        numTotalTests          = $total
        openHandles            = @()
        snapshot               = [ordered]@{
            added = 0; didUpdate = $false; failure = $false; filesAdded = 0
            filesRemoved = 0; filesRemovedList = @(); filesUnmatched = 0
            filesUpdated = 0; matched = 0; total = 0; unchecked = 0
            uncheckedKeyPath = @(); unmatched = 0; updated = 0
        }
        startTime   = $startMs
        success     = ($suiteStatus -eq 'passed')
        testResults = @([ordered]@{
            assertionResults = $assertions
            endTime          = $startMs + 2000
            message          = $message
            startTime        = $startMs + 100
            status           = $suiteStatus
            testExecError    = $null
            testFilePath     = "/code/spectrace/demo/jest/$testFile"
        })
        wasInterrupted = $false
    }

    $report | ConvertTo-Json -Depth 15 |
        Set-Content (Join-Path $dir 'results.json') -Encoding UTF8
    Write-Host "  [jest] $Scenario -OK"
}

New-JestBundle 'passing'
New-JestBundle 'failing-assertion'
New-JestBundle 'failing-timeout'
New-JestBundle 'flaky'

# ---------------------------------------------------------------------------
# TRX fixtures
# ---------------------------------------------------------------------------

function New-TrxBundle([string]$Scenario) {
    $dir = Join-Path $OutputRoot "trx/$Scenario"
    Ensure-Dir $dir

    $runId    = [guid]::NewGuid().ToString()
    $listId   = [guid]::NewGuid().ToString()
    $allId    = [guid]::NewGuid().ToString()

    switch ($Scenario) {
        'passing' {
            $outcome = 'Completed'
            $countersAttr = 'total="3" executed="3" passed="3" failed="0" error="0" timeout="0" aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0"'
            $testData = @(
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ValidCredentials_ReturnsSessionToken';    Class='SpecTrace.Demo.Tests.LoginTests';    Ms=45;  Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ValidCredentials_ReturnsCorrectWelcomeMessage'; Class='SpecTrace.Demo.Tests.LoginTests'; Ms=12; Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ValidCredentials_SetsSessionExpiry';      Class='SpecTrace.Demo.Tests.LoginTests';    Ms=8;   Outcome='Passed'; Error=''; Stack='' }
            )
        }
        'failing-assertion' {
            $outcome = 'Failed'
            $countersAttr = 'total="3" executed="3" passed="2" failed="1" error="0" timeout="0" aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0"'
            $testData = @(
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='CalculateTotal_MultipleItems_ReturnsCorrectSum'; Class='SpecTrace.Demo.Tests.CheckoutTests'; Ms=18; Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ApplyDiscount_TenPercent_ReturnsCorrectAmount'; Class='SpecTrace.Demo.Tests.CheckoutTests'; Ms=12; Outcome='Failed'
                   Error='Assert.Equal() Failure&#xD;&#xA;Expected: 90&#xD;&#xA;Actual:   90.00000000001&#xD;&#xA;&#xD;&#xA;Values are not equal.'
                   Stack='   at SpecTrace.Demo.Tests.CheckoutTests.ApplyDiscount_TenPercent_ReturnsCorrectAmount() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/CheckoutTests.cs:line 18' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='CalculateTotal_EmptyCart_ReturnsZero'; Class='SpecTrace.Demo.Tests.CheckoutTests'; Ms=7; Outcome='Passed'; Error=''; Stack='' }
            )
        }
        'failing-timeout' {
            $outcome = 'Failed'
            $countersAttr = 'total="3" executed="3" passed="2" failed="1" error="0" timeout="1" aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0"'
            $testData = @(
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='SearchByKeyword_KnownProduct_ReturnsResults'; Class='SpecTrace.Demo.Tests.SearchTests'; Ms=32; Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='SearchByKeyword_UnknownProduct_ReturnsEmpty'; Class='SpecTrace.Demo.Tests.SearchTests'; Ms=9; Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='SearchByKeyword_SlowApi_TimesOut'; Class='SpecTrace.Demo.Tests.SearchTests'; Ms=1001; Outcome='Timeout'
                   Error='Test exceeded execution timeout of 1000 milliseconds.'
                   Stack='   at SpecTrace.Demo.Tests.SearchTests.SearchByKeyword_SlowApi_TimesOut() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/SearchTests.cs:line 22' }
            )
        }
        'flaky' {
            $outcome = 'Failed'
            $countersAttr = 'total="3" executed="3" passed="2" failed="1" error="0" timeout="0" aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0"'
            $testData = @(
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ValidCard_ReturnsConfirmationNumber'; Class='SpecTrace.Demo.Tests.PaymentTests'; Ms=28; Outcome='Passed'; Error=''; Stack='' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='PaymentStatus_AfterProcessing_IsSettled'; Class='SpecTrace.Demo.Tests.PaymentTests'; Ms=423; Outcome='Failed'
                   Error='Assert.Equal() Failure&#xD;&#xA;Expected: String "settled"&#xD;&#xA;Actual:   String "unknown"&#xD;&#xA;&#xD;&#xA;Note: This test is known-flaky; the gateway propagates status after a random delay.'
                   Stack='   at SpecTrace.Demo.Tests.PaymentTests.PaymentStatus_AfterProcessing_IsSettled() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/PaymentTests.cs:line 28' }
                @{ Id=[guid]::NewGuid(); ExId=[guid]::NewGuid(); Name='ExpiredCard_ThrowsException'; Class='SpecTrace.Demo.Tests.PaymentTests'; Ms=15; Outcome='Passed'; Error=''; Stack='' }
            )
        }
    }

    $start  = '2024-11-15T10:00:00.0000000+00:00'
    $finish = '2024-11-15T10:00:01.5000000+00:00'

    $resultsXml = ''
    $defsXml    = ''
    $entriesXml = ''

    foreach ($t in $testData) {
        $dur = [TimeSpan]::FromMilliseconds($t.Ms).ToString('hh\:mm\:ss\.fffffff')
        $end = [datetime]::Parse('2024-11-15T10:00:00Z').AddMilliseconds($t.Ms).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        if ($t.Outcome -eq 'Passed') {
            $outputXml = '<Output><StdOut /></Output>'
        } else {
            $outputXml = "<Output><ErrorInfo><Message>$($t.Error)</Message><StackTrace>$($t.Stack)</StackTrace></ErrorInfo></Output>"
        }
        $resultsXml += @"
    <UnitTestResult executionId="$($t.ExId)" testId="$($t.Id)" testName="$($t.Name)" computerName="CI-AGENT" duration="$dur" startTime="2024-11-15T10:00:00.0000000Z" endTime="$end" testType="13cdc9d9-ddb5-4fa4-a97d-d965ccfc6d4b" outcome="$($t.Outcome)" testListId="$listId">
      $outputXml
    </UnitTestResult>
"@
        $defsXml += @"
    <UnitTest name="$($t.Name)" storage="spectrace.demo.tests.dll" id="$($t.Id)">
      <Execution id="$($t.ExId)" />
      <TestMethod className="$($t.Class)" name="$($t.Name)" adapterTypeName="executor://xunit/VsTestRunner2/net" />
    </UnitTest>
"@
        $entriesXml += "    <TestEntry testId=`"$($t.Id)`" executionId=`"$($t.ExId)`" testListId=`"$listId`" />`n"
    }

    $trx = @"
<?xml version="1.0" encoding="UTF-8"?>
<TestRun id="$runId" name="SpecTrace Demo $Scenario run" runUser="demo-runner" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Times creation="$start" queuing="$start" start="$start" finish="$finish" />
  <TestSettings name="default" id="$([guid]::NewGuid())" />
  <Results>
$resultsXml  </Results>
  <TestDefinitions>
$defsXml  </TestDefinitions>
  <TestEntries>
$entriesXml  </TestEntries>
  <TestLists>
    <TestList name="Results Not in a List" id="$listId" />
    <TestList name="All Loaded Results" id="$allId" />
  </TestLists>
  <ResultSummary outcome="$outcome">
    <Counters $countersAttr />
  </ResultSummary>
</TestRun>
"@

    Set-Content (Join-Path $dir 'results.trx') $trx -Encoding UTF8
    Write-Host "  [trx] $Scenario -OK"
}

New-TrxBundle 'passing'
New-TrxBundle 'failing-assertion'
New-TrxBundle 'failing-timeout'
New-TrxBundle 'flaky'

# ---------------------------------------------------------------------------
# JUnit XML fixtures
# ---------------------------------------------------------------------------

function New-JunitBundle([string]$Scenario) {
    $dir = Join-Path $OutputRoot "junit/$Scenario"
    Ensure-Dir $dir

    switch ($Scenario) {
        'passing' {
            $suiteAttr = 'tests="3" passed="3" failures="0" errors="0" skipped="0" time="0.065"'
            $cases = @"
    <testcase name="ValidCredentials_ReturnsSessionToken" classname="SpecTrace.Demo.Tests.LoginTests" time="0.045" />
    <testcase name="ValidCredentials_ReturnsCorrectWelcomeMessage" classname="SpecTrace.Demo.Tests.LoginTests" time="0.012" />
    <testcase name="ValidCredentials_SetsSessionExpiry" classname="SpecTrace.Demo.Tests.LoginTests" time="0.008" />
"@
            $suite = 'LoginTests'
        }
        'failing-assertion' {
            $suiteAttr = 'tests="3" passed="2" failures="1" errors="0" skipped="0" time="0.037"'
            $cases = @"
    <testcase name="CalculateTotal_MultipleItems_ReturnsCorrectSum" classname="SpecTrace.Demo.Tests.CheckoutTests" time="0.018" />
    <testcase name="ApplyDiscount_TenPercent_ReturnsCorrectAmount" classname="SpecTrace.Demo.Tests.CheckoutTests" time="0.012">
      <failure message="Assert.Equal() Failure&#xA;Expected: 90&#xA;Actual:   90.00000000001&#xA;Values are not equal." type="Xunit.Sdk.EqualException">
   at SpecTrace.Demo.Tests.CheckoutTests.ApplyDiscount_TenPercent_ReturnsCorrectAmount() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/CheckoutTests.cs:line 18
      </failure>
    </testcase>
    <testcase name="CalculateTotal_EmptyCart_ReturnsZero" classname="SpecTrace.Demo.Tests.CheckoutTests" time="0.007" />
"@
            $suite = 'CheckoutTests'
        }
        'failing-timeout' {
            $suiteAttr = 'tests="3" passed="2" failures="0" errors="1" skipped="0" time="1.042"'
            $cases = @"
    <testcase name="SearchByKeyword_KnownProduct_ReturnsResults" classname="SpecTrace.Demo.Tests.SearchTests" time="0.032" />
    <testcase name="SearchByKeyword_UnknownProduct_ReturnsEmpty" classname="SpecTrace.Demo.Tests.SearchTests" time="0.009" />
    <testcase name="SearchByKeyword_SlowApi_TimesOut" classname="SpecTrace.Demo.Tests.SearchTests" time="1.001">
      <error message="Test exceeded execution timeout of 1000 milliseconds." type="Microsoft.VisualStudio.TestPlatform.ObjectModel.TestTimeoutException">
   at SpecTrace.Demo.Tests.SearchTests.SearchByKeyword_SlowApi_TimesOut() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/SearchTests.cs:line 22
      </error>
    </testcase>
"@
            $suite = 'SearchTests'
        }
        'flaky' {
            $suiteAttr = 'tests="3" passed="2" failures="1" errors="0" skipped="0" time="0.466"'
            $cases = @"
    <testcase name="ValidCard_ReturnsConfirmationNumber" classname="SpecTrace.Demo.Tests.PaymentTests" time="0.028" />
    <testcase name="PaymentStatus_AfterProcessing_IsSettled" classname="SpecTrace.Demo.Tests.PaymentTests" time="0.423">
      <failure message="Assert.Equal() Failure&#xA;Expected: String &quot;settled&quot;&#xA;Actual:   String &quot;unknown&quot;&#xA;&#xA;Note: This test is known-flaky; gateway propagates status after a random delay." type="Xunit.Sdk.EqualException">
   at SpecTrace.Demo.Tests.PaymentTests.PaymentStatus_AfterProcessing_IsSettled() in /code/spectrace/demo/dotnet/SpecTrace.Demo.Tests/PaymentTests.cs:line 28
      </failure>
    </testcase>
    <testcase name="ExpiredCard_ThrowsException" classname="SpecTrace.Demo.Tests.PaymentTests" time="0.015" />
"@
            $suite = 'PaymentTests'
        }
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<testsuites>
  <testsuite name="$suite" $suiteAttr timestamp="2024-11-15T10:00:00">
$cases  </testsuite>
</testsuites>
"@

    Set-Content (Join-Path $dir 'results.xml') $xml -Encoding UTF8
    Write-Host "  [junit] $Scenario -OK"
}

New-JunitBundle 'passing'
New-JunitBundle 'failing-assertion'
New-JunitBundle 'failing-timeout'
New-JunitBundle 'flaky'

Write-Host ''
Write-Host "All fixture bundles written to: $OutputRoot"
Write-Host 'Run scripts/verify-fixtures.ps1 to confirm all expected files exist.'
