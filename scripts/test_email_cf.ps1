<#
.SYNOPSIS
    End-to-end smoke test for the Phase 2 email Cloud Functions.

.DESCRIPTION
    1. Signs in to Firebase with the test account (REST API).
    2. Fetches the authenticated user's UID.
    3. Creates a minimal factoryOrder doc directly in Firestore (REST).
    4. Calls the sendFactoryEmails Cloud Function.
    5. Creates a minimal supplierOrder doc directly in Firestore (REST).
    6. Calls the sendSupplierEmails Cloud Function.
    7. Prints a pass/fail summary.

.NOTES
    Requires: PowerShell 5+ with Invoke-RestMethod.
    Run from the project root:  .\scripts\test_email_cf.ps1
    The test creates real documents in Firestore under the test account
    and sends real emails via the configured SMTP (Gmail).
    Delete the test docs from Firebase Console afterwards if needed.
#>

param(
    [string]$TestEmail    = "karamony1@gmail.com",
    [string]$TestPassword = "",           # leave blank to be prompted securely
    [string]$AppUrl       = "https://ma5zony.web.app"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Prompt for password if not supplied via parameter
if ([string]::IsNullOrEmpty($TestPassword)) {
    $securePwd  = Read-Host "Firebase password for $TestEmail" -AsSecureString
    $credential = New-Object System.Management.Automation.PSCredential($TestEmail, $securePwd)
    $TestPassword = $credential.GetNetworkCredential().Password
}
$FirebaseApiKey   = "AIzaSyCuDIr8QoaXd7ElhxaegXj3JQZZl1XrhlY"
$ProjectId        = "ma5zony"
$CfSuffix         = "-rjv64oud6a-uc.a.run.app"
$FirestoreBase    = "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/(default)/documents"

# ─── Helpers ────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) { Write-Host "`n[STEP] $msg" -ForegroundColor Cyan }
function Write-Pass([string]$msg) { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

function Invoke-CF([string]$FunctionName, [hashtable]$Body, [string]$IdToken) {
    $url = "https://$FunctionName$CfSuffix"
    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $IdToken"
    }
    try {
        $response = Invoke-RestMethod -Uri $url -Method POST `
            -Headers $headers -Body ($Body | ConvertTo-Json -Depth 5)
        return $response
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $body = $_.ErrorDetails.Message
        throw "CF $FunctionName returned HTTP $statusCode : $body"
    }
}

function New-FirestoreDoc([string]$Collection, [hashtable]$Fields, [string]$AccessToken) {
    $url = "$FirestoreBase/$Collection"
    $headers = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $AccessToken"
    }
    $fsFields = @{}
    foreach ($kv in $Fields.GetEnumerator()) {
        $v = $kv.Value
        if ($v -is [string])  { $fsFields[$kv.Key] = @{ stringValue  = $v } }
        elseif ($v -is [int] -or $v -is [long]) { $fsFields[$kv.Key] = @{ integerValue = "$v" } }
        elseif ($v -is [bool]) { $fsFields[$kv.Key] = @{ booleanValue = $v } }
    }
    $body = @{ fields = $fsFields } | ConvertTo-Json -Depth 10
    $resp = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body
    # Extract document ID from the name field
    return ($resp.name -split "/")[-1]
}

# ─── Step 1: Sign in ────────────────────────────────────────────────────────

Write-Step "Signing in as $TestEmail ..."
$signInUrl  = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$FirebaseApiKey"
$signInBody = "{`"email`":`"$TestEmail`",`"password`":`"$TestPassword`",`"returnSecureToken`":true}"
try {
    $signIn = Invoke-RestMethod -Uri $signInUrl -Method POST `
              -ContentType "application/json" -Body $signInBody
} catch {
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $errMsg = ($reader.ReadToEnd() | ConvertFrom-Json).error.message
    throw "Firebase sign-in failed: $errMsg (check email/password)"
}

$IdToken = $signIn.idToken
$Uid     = $signIn.localId
Write-Pass "Signed in. UID = $Uid"

# ─── Step 2: Create a test factoryOrder document ────────────────────────────

Write-Step "Creating test factoryOrder in Firestore ..."
$testProductionOrderId = "test_po_$(Get-Random)"
$testAccessToken       = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })

$factoryOrderId = New-FirestoreDoc -Collection "factoryOrders" -Fields @{
    productionOrderId = $testProductionOrderId
    ownerUid          = $Uid
    supplierId        = "test_supplier"
    supplierName      = "Test Supplier (automated)"
    supplierEmail     = $TestEmail   # send to yourself
    status            = "pending"
    accessToken       = $testAccessToken
} -AccessToken $IdToken

Write-Pass "Created factoryOrder/$factoryOrderId"

# ─── Step 3: Call sendFactoryEmails ─────────────────────────────────────────

Write-Step "Calling sendFactoryEmails CF ..."
try {
    $result = Invoke-CF -FunctionName "sendfactoryemails" -Body @{
        uid               = $Uid
        productionOrderId = $testProductionOrderId
        appUrl            = $AppUrl
    } -IdToken $IdToken

    $sent   = @($result.results | Where-Object { $_.status -eq "sent"   }).Count
    $failed = @($result.results | Where-Object { $_.status -eq "failed" }).Count

    if ($sent -gt 0) {
        Write-Pass "sendFactoryEmails: $sent email(s) sent, $failed failed"
        Write-Host "   Email delivered to: $($result.results | Where-Object { $_.status -eq 'sent' } | ForEach-Object { $_.email } | Join-String -Separator ', ')"
    } else {
        Write-Fail "sendFactoryEmails: 0 emails sent. Failures: $($result.results | ConvertTo-Json -Depth 3)"
    }
} catch {
    Write-Fail "sendFactoryEmails threw: $_"
}

# ─── Step 4: Create a test supplierOrder document ───────────────────────────

Write-Step "Creating test supplierOrder in Firestore ..."
$testPurchaseOrderId   = "test_purchase_$(Get-Random)"
$testSupplierAccessTok = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })

# Firestore doesn't allow nested arrays in the simple helper above;
# use the REST API directly for the items array.
$supplierOrderUrl  = "$FirestoreBase/supplierOrders"
$supplierOrderBody = @{
    fields = @{
        purchaseOrderId = @{ stringValue = $testPurchaseOrderId }
        ownerUid        = @{ stringValue = $Uid }
        supplierId      = @{ stringValue = "test_supplier" }
        supplierName    = @{ stringValue = "Test Supplier (automated)" }
        supplierEmail   = @{ stringValue = $TestEmail }
        status          = @{ stringValue = "pending" }
        accessToken     = @{ stringValue = $testSupplierAccessTok }
        items           = @{
            arrayValue = @{
                values = @(
                    @{
                        mapValue = @{
                            fields = @{
                                productName = @{ stringValue = "Test Product" }
                                sku         = @{ stringValue = "TEST-SKU-001" }
                                quantity    = @{ integerValue = "5" }
                                unitCost    = @{ doubleValue  = 10.0 }
                            }
                        }
                    }
                )
            }
        }
    }
} | ConvertTo-Json -Depth 15

$supplierOrderResp = Invoke-RestMethod -Uri $supplierOrderUrl -Method POST `
    -ContentType "application/json" `
    -Headers @{ Authorization = "Bearer $IdToken" } `
    -Body $supplierOrderBody

$supplierOrderId = ($supplierOrderResp.name -split "/")[-1]
Write-Pass "Created supplierOrder/$supplierOrderId"

# ─── Step 5: Call sendSupplierEmails ────────────────────────────────────────

Write-Step "Calling sendSupplierEmails CF ..."
try {
    $result2 = Invoke-CF -FunctionName "sendsupplieremails" -Body @{
        uid             = $Uid
        purchaseOrderId = $testPurchaseOrderId
        appUrl          = $AppUrl
    } -IdToken $IdToken

    $sent2   = @($result2.results | Where-Object { $_.status -eq "sent"   }).Count
    $failed2 = @($result2.results | Where-Object { $_.status -eq "failed" }).Count

    if ($sent2 -gt 0) {
        Write-Pass "sendSupplierEmails: $sent2 email(s) sent, $failed2 failed"
        Write-Host "   Email delivered to: $($result2.results | Where-Object { $_.status -eq 'sent' } | ForEach-Object { $_.email } | Join-String -Separator ', ')"
    } else {
        Write-Fail "sendSupplierEmails: 0 emails sent. Failures: $($result2.results | ConvertTo-Json -Depth 3)"
    }
} catch {
    Write-Fail "sendSupplierEmails threw: $_"
}

# ─── Summary ────────────────────────────────────────────────────────────────

Write-Host "`n───────────────────────────────────────────────────────"
Write-Host "Test complete. Check $TestEmail inbox for 2 test emails."
Write-Host "Clean-up: delete factoryOrders/$factoryOrderId and"
Write-Host "          supplierOrders/$supplierOrderId from Firebase Console."
Write-Host "───────────────────────────────────────────────────────"
