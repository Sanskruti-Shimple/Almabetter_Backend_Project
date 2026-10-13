[CmdletBinding()]
param(
  [string]$SubscriptionId = '',
  [string]$ResourceGroupName = 'rg-almabetter-backend',
  [string]$Location = 'centralus',
  [string]$EnvironmentName = 'dev'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot 'infra\main.bicep'
$parametersPath = Join-Path $repoRoot 'infra\main.parameters.json'
$deploymentName = "almabetter-$EnvironmentName-$(Get-Date -Format 'yyyyMMddHHmmss')"

function Invoke-Az {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  & az @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed with exit code $LASTEXITCODE`: az $($Arguments -join ' ')"
  }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw 'Azure CLI is required. Install it, open a new PowerShell window, and rerun this script.'
}

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  $accountJson = & az account show --output json 2>$null
} else {
  $accountJson = & az account show --subscription $SubscriptionId --output json 2>$null
}
if ($LASTEXITCODE -ne 0) {
  throw "Azure CLI is not authenticated. Run 'az login' and rerun this script."
}
$account = $accountJson | ConvertFrom-Json
if ($account.state -ne 'Enabled') {
  throw "The selected Azure subscription is not enabled."
}
$SubscriptionId = $account.id
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId)

$principalType = 'User'
$principalId = ''
if ($account.user.type -eq 'user') {
  $principalId = (& az ad signed-in-user show --query id --output tsv)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
    throw 'Could not resolve the signed-in user object ID required for the initial Key Vault secret write.'
  }
} elseif ($account.user.type -eq 'servicePrincipal') {
  $principalType = 'ServicePrincipal'
  $principalId = (& az ad sp show --id $account.user.name --query id --output tsv)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($principalId)) {
    throw 'Could not resolve the service-principal object ID required for the initial Key Vault secret write.'
  }
} else {
  throw "Unsupported Azure CLI identity type '$($account.user.type)'."
}

Invoke-Az @('bicep', 'build', '--file', $templatePath)
Invoke-Az @('group', 'create', '--name', $ResourceGroupName, '--location', $Location, '--output', 'none')

$deploymentParameters = @(
  "@$parametersPath",
  "environmentName=$EnvironmentName",
  "location=$Location",
  "deploymentPrincipalId=$principalId",
  "deploymentPrincipalType=$principalType"
)
$whatIfArguments = @('deployment', 'group', 'what-if', '--name', $deploymentName, '--resource-group', $ResourceGroupName, '--template-file', $templatePath, '--parameters') + $deploymentParameters + @('--no-pretty-print')
Invoke-Az $whatIfArguments

$createArguments = @('deployment', 'group', 'create', '--name', $deploymentName, '--resource-group', $ResourceGroupName, '--template-file', $templatePath, '--parameters') + $deploymentParameters + @('--output', 'json')
$deploymentJson = & az @createArguments
if ($LASTEXITCODE -ne 0) {
  throw 'Azure infrastructure deployment failed. Review the Azure CLI error output before retrying.'
}
$deployment = $deploymentJson | ConvertFrom-Json
$outputs = $deployment.properties.outputs
$appName = $outputs.appName.value
$appHostName = $outputs.appHostName.value
$cosmosAccountName = $outputs.cosmosAccountName.value
$keyVaultName = $outputs.keyVaultName.value
$mongoDatabaseName = $outputs.mongoDatabaseName.value

$primaryKey = & az cosmosdb keys list --name $cosmosAccountName --resource-group $ResourceGroupName --type keys --query primaryMasterKey --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($primaryKey)) {
  throw 'Could not retrieve the Cosmos DB MongoDB primary key.'
}
$encodedKey = [Uri]::EscapeDataString($primaryKey)
$mongoUri = "mongodb://${cosmosAccountName}:${encodedKey}@${cosmosAccountName}.mongo.cosmos.azure.com:10255/${mongoDatabaseName}?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000&appName=@${cosmosAccountName}@"
$primaryKey = $null
$encodedKey = $null

$secretPath = Join-Path $env:TEMP ("almabetter-mongo-uri-" + [Guid]::NewGuid().ToString('N') + '.txt')
$secretStored = $false
try {
  [System.IO.File]::WriteAllText($secretPath, $mongoUri, [System.Text.UTF8Encoding]::new($false))
  for ($attempt = 1; $attempt -le 8; $attempt++) {
    & az keyvault secret set --vault-name $keyVaultName --name 'mongodb-uri' --file $secretPath --encoding utf-8 --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
      $secretStored = $true
      break
    }
    if ($attempt -lt 8) {
      Start-Sleep -Seconds 10
    }
  }
} finally {
  $mongoUri = $null
  if (Test-Path $secretPath) {
    Remove-Item -LiteralPath $secretPath -Force
  }
}
if (-not $secretStored) {
  throw "Could not write the MongoDB URI to Key Vault '$keyVaultName'. Verify the deployment identity has Key Vault Secrets Officer access, then rerun the script."
}

$stagingPath = Join-Path $env:TEMP ("almabetter-deploy-" + [Guid]::NewGuid().ToString('N'))
$zipPath = "$stagingPath.zip"
try {
  New-Item -ItemType Directory -Path $stagingPath | Out-Null
  Copy-Item (Join-Path $repoRoot 'package.json') $stagingPath
  $lockFile = Join-Path $repoRoot 'package-lock.json'
  if (Test-Path $lockFile) {
    Copy-Item $lockFile $stagingPath
  }
  $sourceRoot = Join-Path $repoRoot 'src'
  $sourceFiles = Get-ChildItem -Path $sourceRoot -File -Recurse | Where-Object { $_.Name -ne '.env' }
  foreach ($sourceFile in $sourceFiles) {
    $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $destinationPath = Join-Path (Join-Path $stagingPath 'src') $relativePath
    $destinationDirectory = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    Copy-Item $sourceFile.FullName $destinationPath
  }
  Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $zipPath -Force
  $deployErrorPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & az webapp deploy --resource-group $ResourceGroupName --name $appName --src-path $zipPath --type zip --output none 2>$null
  $deployExitCode = $LASTEXITCODE
  $ErrorActionPreference = $deployErrorPreference
  if ($deployExitCode -ne 0) {
    Write-Warning 'OneDeploy failed; retrying through the Kudu zip-push deployment endpoint.'
    Invoke-Az @('webapp', 'deployment', 'source', 'config-zip', '--resource-group', $ResourceGroupName, '--name', $appName, '--src', $zipPath, '--timeout', '600', '--output', 'none')
  }
  Invoke-Az @('webapp', 'restart', '--resource-group', $ResourceGroupName, '--name', $appName, '--output', 'none')
} finally {
  if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }
  if (Test-Path $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
  }
}

$endpoint = "https://$appHostName/subscribers"
$healthy = $false
$lastHealthError = ''
for ($attempt = 1; $attempt -le 18; $attempt++) {
  try {
    $response = Invoke-WebRequest -Uri $endpoint -Method Get -TimeoutSec 15 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
      $healthy = $true
      break
    }
  } catch {
    $lastHealthError = $_.Exception.Message
    Start-Sleep -Seconds 10
  }
}
if (-not $healthy) {
  throw "Deployment completed, but the API did not return HTTP 200 from $endpoint. Last probe error: $lastHealthError. Check App Service logs and Key Vault reference status."
}

Write-Host "Deployment succeeded. API endpoint: https://$appHostName"
Write-Host "Subscriber list: $endpoint"
Write-Host "Azure resource group: $ResourceGroupName"
