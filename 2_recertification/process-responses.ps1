# process-responses.ps1
# Traitement des retours managers suite à la campagne de recertification
# Génère les LDIF de révocation + rapport de clôture de campagne
# Conformité : ISO 27001:2022 A.5.18 | NIST AC-2(4)
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull

[CmdletBinding()]
param(
    [string]$CampaignDir  = "../output",
    [string]$CampaignName = "Q$(([Math]::Ceiling((Get-Date).Month / 3)))-$(Get-Date -Format 'yyyy')",
    [string]$OutputDir    = "../output",
    [string]$LogDir       = "../logs",
    [string]$DomainDN     = "DC=lab,DC=local",
    [switch]$DryRun
)

$timestamp      = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile        = "$LogDir/${timestamp}_process-responses.log"
$RevokeLDIF     = "$OutputDir/revoke_campaign_${CampaignName}_$timestamp.ldif"
$CampaignReport = "$OutputDir/campaign_report_${CampaignName}_$timestamp.csv"
$null = New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) { "INFO"{"Cyan"} "OK"{"Green"} "WARN"{"Yellow"} "HIGH"{"Red"} "DRY"{"Magenta"} default{"White"} }
    Write-Host $line -ForegroundColor $color
}

Write-Log "INFO" "=== TRAITEMENT RÉPONSES CAMPAGNE : $CampaignName ==="

# Charger tous les fichiers de réponses de la campagne
$campaignFolder = "$CampaignDir/campaign_$CampaignName"
if (-not (Test-Path $campaignFolder)) {
    Write-Log "HIGH" "Dossier campagne introuvable : $campaignFolder"
    exit 1
}

$csvFiles = Get-ChildItem -Path $campaignFolder -Filter "recertification_*.csv"
Write-Log "INFO" "Fichiers de réponses trouvés : $($csvFiles.Count)"

$AllEntries  = @()
$ToRevoke    = @()
$Certified   = @()
$Exceptions  = @()
$NoPending   = @()  # Aucune réponse

foreach ($file in $csvFiles) {
    $entries = Import-Csv -Path $file.FullName -Encoding UTF8 -Delimiter ";"
    foreach ($entry in $entries) {
        $AllEntries += $entry
        switch ($entry.Decision.Trim()) {
            "Certifié"   { $Certified += $entry }
            "Révoquer"   { $ToRevoke  += $entry }
            "Exception"  { $Exceptions += $entry }
            ""           { $NoPending  += $entry }
            default      { Write-Log "WARN" "Décision inconnue '$($entry.Decision)' pour $($entry.SamAccountName)" }
        }
    }
}

Write-Log "INFO" "Certifiés : $($Certified.Count) | À révoquer : $($ToRevoke.Count) | Exceptions : $($Exceptions.Count) | Sans réponse : $($NoPending.Count)"

# ─── Génération LDIF de révocation ────────────────────────────────────────────

if ($ToRevoke.Count -gt 0) {
    Set-Content -Path $RevokeLDIF -Value "# LDIF Révocations — Campagne $CampaignName — $(Get-Date -Format 'dd/MM/yyyy')" -Encoding UTF8

    foreach ($entry in $ToRevoke) {
        $groups = $entry.CurrentGroups -split ";"
        foreach ($group in $groups) {
            $group = $group.Trim()
            if ([string]::IsNullOrWhiteSpace($group)) { continue }

            $ldifBlock = @"

# Révocation décidée par $($entry.ManagerName) — Motif : $($entry.JustificationRevoke)
dn: CN=$group,OU=Groups,$DomainDN
changetype: modify
delete: member
member: CN=$($entry.DisplayName),OU=Users,$DomainDN

"@
            Add-Content -Path $RevokeLDIF -Value $ldifBlock -Encoding UTF8
        }
        $action = if ($DryRun) { "SIMULATION révocation" } else { "RÉVOQUÉ" }
        Write-Log "OK" "$action : $($entry.SamAccountName) — Motif : $($entry.JustificationRevoke)"
    }
}

# ─── Rapport de campagne ───────────────────────────────────────────────────────

$Report = @()
foreach ($e in $AllEntries) {
    $Report += [PSCustomObject]@{
        CampaignID    = $CampaignName
        SamAccountName= $e.SamAccountName
        DisplayName   = $e.DisplayName
        Department    = $e.Department
        ManagerName   = $e.ManagerName
        Decision      = if ($e.Decision) { $e.Decision } else { "SANS RÉPONSE" }
        Justification = if ($e.JustificationRevoke) { $e.JustificationRevoke } elseif ($e.JustificationException) { $e.JustificationException } else { "" }
        ProcessedDate = (Get-Date -Format "yyyy-MM-dd")
    }
}
$Report | Export-Csv -Path $CampaignReport -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host ""
Write-Host "  SYNTHÈSE CAMPAGNE $CampaignName" -ForegroundColor Blue
Write-Host "  ─────────────────────────────────────────────"
Write-Host "  Total comptes : $($AllEntries.Count)" -ForegroundColor Cyan
Write-Host "  Certifiés     : $($Certified.Count)" -ForegroundColor Green
Write-Host "  Révoqués      : $($ToRevoke.Count)" -ForegroundColor Red
Write-Host "  Exceptions    : $($Exceptions.Count)" -ForegroundColor Yellow
Write-Host "  Sans réponse  : $($NoPending.Count) → escalate-pending.ps1" -ForegroundColor Yellow
Write-Host ""

Write-Log "INFO" "=== FIN TRAITEMENT — Rapport : $CampaignReport ==="
if ($NoPending.Count -gt 0) {
    Write-Log "WARN" "$($NoPending.Count) compte(s) sans réponse → exécuter escalate-pending.ps1"
}
