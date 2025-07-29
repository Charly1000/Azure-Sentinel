# Voraussetzungen:
# - Azure Az PowerShell-Modul installiert
# - Angemeldet mit `Connect-AzAccount`
# - Zugriff auf Microsoft Sentinel-Workspace

param (
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory=$true)]
    [string]$RepoPath  # z. B. "C:\Repos\SentinelContent"
)

# Setze das Abo
Set-AzContext -SubscriptionId $SubscriptionId

# Helper-Funktion: JSON-Dateien einlesen
function Get-FilesFromFolder($folderPath) {
    return Get-ChildItem -Path $folderPath -Filter *.json -Recurse | ForEach-Object {
        Get-Content $_.FullName -Raw | ConvertFrom-Json
    }
}

# Deploy Analytics Rules
Write-Host "`n🔍 Deploying Analytics Rules..."
$analyticsRules = Get-FilesFromFolder "$RepoPath\AnalyticsRules"
foreach ($rule in $analyticsRules) {
    New-AzSentinelAlertRule -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName `
        -Kind Scheduled `
        -DisplayName $rule.properties.displayName `
        -Description $rule.properties.description `
        -Query $rule.properties.query `
        -QueryFrequency $rule.properties.queryFrequency `
        -QueryPeriod $rule.properties.queryPeriod `
        -Severity $rule.properties.severity `
        -Enabled $rule.properties.enabled
}

# Deploy Automation Rules
Write-Host "`n⚙️ Deploying Automation Rules..."
$automationRules = Get-FilesFromFolder "$RepoPath\AutomationRules"
foreach ($rule in $automationRules) {
    New-AzSentinelAutomationRule `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName `
        -RuleId $rule.name `
        -DisplayName $rule.properties.displayName `
        -Order $rule.properties.order `
        -Actions $rule.properties.actions
}

# Deploy Hunting Queries
Write-Host "`n🕵️ Deploying Hunting Queries..."
$huntingQueries = Get-FilesFromFolder "$RepoPath\HuntingQueries"
foreach ($query in $huntingQueries) {
    New-AzSentinelHuntingRule `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName `
        -DisplayName $query.properties.displayName `
        -Query $query.properties.query `
        -Severity $query.properties.severity `
        -Enabled $true
}

# Deploy Parsers (ASIM oder eigene Kusto Functions)
Write-Host "`n🔍 Deploying Parsers..."
$parsers = Get-ChildItem "$RepoPath\Parsers" -Filter *.kql
foreach ($parser in $parsers) {
    $name = $parser.BaseName
    $query = Get-Content $parser.FullName -Raw
    New-AzOperationalInsightsSavedSearch `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName `
        -SavedSearchId $name `
        -DisplayName $name `
        -Category "Parsers" `
        -Query $query `
        -Version 1
}

# Deploy Playbooks (ARM Templates)
Write-Host "`n🤖 Deploying Playbooks..."
$playbookTemplates = Get-ChildItem "$RepoPath\Playbooks" -Filter *.json
foreach ($template in $playbookTemplates) {
    $playbookName = (Get-Item $template).BaseName
    New-AzDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $template.FullName `
        -Name "Deploy_$playbookName"
}

# Deploy Workbooks
Write-Host "`n📊 Deploying Workbooks..."
$workbooks = Get-FilesFromFolder "$RepoPath\Workbooks"
foreach ($wb in $workbooks) {
    New-AzOperationalInsightsIntelligencePack `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $WorkspaceName `
        -Name $wb.name `
        -DisplayName $wb.properties.displayName `
        -SerializedData ($wb | ConvertTo-Json -Depth 10)
}

Write-Host "`n✅ Deployment abgeschlossen!"
