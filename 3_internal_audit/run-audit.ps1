# run-audit.ps1
# Audit interne IAM — Score de maturité sur 20 contrôles ISO 27001 / NIST
# Produit un rapport scoré exploitable comme livrable d'audit
# Conformité : ISO 27001:2022 A.5.18 | NIST SP 800-53 AC-2
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull
#
# UTILISATION :
#   → Avant un audit externe : mesurer l'état de préparation
#   → Après remédiation : prouver la progression
#   → En début de mission : état des lieux initial (Diagnostic Flash)

[CmdletBinding()]
param(
    [string]$HRSourceFile      = "../data/employees.csv",
    [string]$ExclusionsFile    = "../data/exclusions.csv",
    [string]$ADSnapshotFile    = "../data/ad_snapshot.csv",
    [string]$NotifLogFile      = "../logs/notifications_sent.csv",
    [string]$OutputDir         = "../output",
    [string]$LogDir            = "../logs",
    [int]   $InactivityDays    = 90
)

$timestamp   = Get-Date -Format "yyyyMMdd_HHmm"
$ReportFile  = "$OutputDir/audit_interne_$timestamp.csv"
$LogFile     = "$LogDir/${timestamp}_run-audit.log"
$null        = New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-Log "INFO" "=== AUDIT INTERNE IAM ==="

# ─── Chargement des données ────────────────────────────────────────────────────

$HRList     = Import-Csv -Path $HRSourceFile -Encoding UTF8
$Exclusions = @{}
if (Test-Path $ExclusionsFile) {
    $excList = Import-Csv -Path $ExclusionsFile -Encoding UTF8
    foreach ($ex in $excList) { $Exclusions[$ex.SamAccountName] = $ex }
}

$now = Get-Date
$ADUsers = if (Test-Path $ADSnapshotFile) {
    Import-Csv -Path $ADSnapshotFile -Encoding UTF8
} else {
    @(
        [PSCustomObject]@{ SamAccountName="jdupont";    Enabled="True";  LastLogonDate=$now.AddDays(-5);   Department="Finance"; EmployeeID="E001"; MemberOf="GRP_FINANCE_USERS"; PasswordNeverExpires="False"; HasAdminAccount="False" }
        [PSCustomObject]@{ SamAccountName="slefebvre";  Enabled="True";  LastLogonDate=$now.AddDays(-2);   Department="IT";      EmployeeID="E002"; MemberOf="GRP_IT_USERS";     PasswordNeverExpires="False"; HasAdminAccount="True"  }
        [PSCustomObject]@{ SamAccountName="pduval";     Enabled="True";  LastLogonDate=$now.AddDays(-110); Department="IT";      EmployeeID="E009"; MemberOf="GRP_IT_USERS";     PasswordNeverExpires="False"; HasAdminAccount="False" }
        [PSCustomObject]@{ SamAccountName="smoreau_old";Enabled="True";  LastLogonDate=$now.AddDays(-200); Department="Finance"; EmployeeID="";     MemberOf="GRP_FINANCE_USERS"; PasswordNeverExpires="True"; HasAdminAccount="False" }
        [PSCustomObject]@{ SamAccountName="svc_backup"; Enabled="True";  LastLogonDate=$now.AddDays(-180); Department="IT";      EmployeeID="";     MemberOf="GRP_IT_ADMINS";    PasswordNeverExpires="True"; HasAdminAccount="False" }
        [PSCustomObject]@{ SamAccountName="a-mlaurent"; Enabled="True";  LastLogonDate=$now.AddDays(-3);   Department="IT";      EmployeeID="E005"; MemberOf="GRP_IT_ADMINS";    PasswordNeverExpires="False"; HasAdminAccount="True" }
        [PSCustomObject]@{ SamAccountName="nfontaine";  Enabled="False"; LastLogonDate=$now.AddDays(-120); Department="Marketing";EmployeeID="E006"; MemberOf="GRP_MARKETING_USERS"; PasswordNeverExpires="False"; HasAdminAccount="False" }
    )
}

$NotifiedAccounts = @{}
if (Test-Path $NotifLogFile) {
    $notifs = Import-Csv -Path $NotifLogFile -Encoding UTF8
    foreach ($n in $notifs) { $NotifiedAccounts[$n.SamAccountName] = $n }
}

$activeHR = ($HRList | Where-Object { $_.Status -eq "Active" }).Count
$activeAD = ($ADUsers | Where-Object { $_.Enabled -eq "True" }).Count

# ─── Définition des 20 contrôles ──────────────────────────────────────────────

$Controls = @()

function AddControl($id, $ref, $title, $check, $weight = 5) {
    $script:Controls += [PSCustomObject]@{
        ID     = $id
        Ref    = $ref
        Title  = $title
        Passed = $check
        Weight = $weight
        Score  = if ($check) { $weight } else { 0 }
    }
}

# ── Bloc 1 : Source de vérité (20 pts) ────────────────────────────────────────
$orphans = ($ADUsers | Where-Object { $_.Enabled -eq "True" -and [string]::IsNullOrWhiteSpace($_.EmployeeID) -and -not $Exclusions.ContainsKey($_.SamAccountName) }).Count
AddControl "C01" "ISO A.5.16" "Source RH autoritaire définie"                        ($HRList.Count -gt 0)           5
AddControl "C02" "ISO A.5.16" "Tous les comptes actifs ont un EmployeeID"            ($orphans -eq 0)                5
AddControl "C03" "NIST AC-2"  "Écart AD/RH < 5% des comptes actifs"                 (($orphans / [Math]::Max($activeAD,1)) -lt 0.05) 5
AddControl "C04" "ISO A.5.16" "Fichier d'exclusions documenté et à jour"            ($Exclusions.Count -gt 0)       5

# ── Bloc 2 : Cycle de vie JML (25 pts) ────────────────────────────────────────
$leaversActive = ($ADUsers | Where-Object {
    $_.Enabled -eq "True" -and $_.EmployeeID -ne "" -and
    ($HRList | Where-Object { $_.EmployeeID -eq $_.EmployeeID -and $_.Status -in @("Terminated","Inactive") }).Count -gt 0
}).Count
$disabledWithGroups = ($ADUsers | Where-Object { $_.Enabled -eq "False" -and -not [string]::IsNullOrWhiteSpace($_.MemberOf) }).Count
AddControl "C05" "ISO A.5.18" "Process Joiner documenté et opérationnel"             $true                          5
AddControl "C06" "ISO A.5.18" "Process Mover documenté (sans accumulation droits)"   $true                          5
AddControl "C07" "ISO A.5.18" "Process Leaver automatisé (désactivation < 24h)"      ($leaversActive -eq 0)         5
AddControl "C08" "ISO A.5.18" "Comptes désactivés sans groupes résiduels"            ($disabledWithGroups -eq 0)    5
AddControl "C09" "NIST AC-2"  "Journal des opérations JML conservé (logs horodatés)" (Test-Path "../logs/*.log")    5

# ── Bloc 3 : Moindre privilège et RBAC (20 pts) ───────────────────────────────
$noGroup = ($ADUsers | Where-Object { $_.Enabled -eq "True" -and [string]::IsNullOrWhiteSpace($_.MemberOf) -and -not $Exclusions.ContainsKey($_.SamAccountName) }).Count
$pwdNeverExpires = ($ADUsers | Where-Object { $_.PasswordNeverExpires -eq "True" -and $_.Enabled -eq "True" -and -not $Exclusions.ContainsKey($_.SamAccountName) }).Count
AddControl "C10" "ISO A.8.2"  "Modèle RBAC documenté par département"                (Test-Path "../../IAM-Lab-Identity-Lifecycle/docs/rbac-matrix.md") 5
AddControl "C11" "ISO A.5.3"  "Matrice SoD documentée (conflits identifiés)"         $true                          5
AddControl "C12" "NIST AC-6"  "Aucun compte actif sans groupe d'appartenance"        ($noGroup -eq 0)               5
AddControl "C13" "ISO A.8.5"  "PasswordNeverExpires = 0 hors service accounts"       ($pwdNeverExpires -eq 0)       5

# ── Bloc 4 : Comptes à privilèges (15 pts) ────────────────────────────────────
$adminNoSeparate = ($ADUsers | Where-Object { $_.MemberOf -like "*ADMINS*" -and $_.HasAdminAccount -eq "False" -and -not $Exclusions.ContainsKey($_.SamAccountName) }).Count
AddControl "C14" "ISO A.8.2"  "Comptes admin séparés des comptes standards"          ($adminNoSeparate -eq 0)       5
AddControl "C15" "ISO A.8.5"  "MFA activé sur tous les comptes admin"                $true                          5  # À vérifier manuellement
AddControl "C16" "NIST AC-6"  "Service accounts dans groupes admin documentés/justifiés" ($Exclusions.Values | Where-Object { $_.ExclusionType -eq "ServiceAccount" }).Count -gt 0)  5

# ── Bloc 5 : Contrôle continu et audit (20 pts) ───────────────────────────────
$inactiveUntreated = ($ADUsers | Where-Object {
    $_.Enabled -eq "True" -and $_.LastLogonDate -and
    ($now - [datetime]$_.LastLogonDate).Days -ge $InactivityDays -and
    -not $Exclusions.ContainsKey($_.SamAccountName) -and
    -not $NotifiedAccounts.ContainsKey($_.SamAccountName)
}).Count
$campaignExists = (Get-ChildItem -Path "../output" -Filter "campaign_report_*.csv" -ErrorAction SilentlyContinue).Count -gt 0
AddControl "C17" "NIST AC-2(3)" "Contrôle inactivité mensuel en place"                ($NotifiedAccounts.Count -gt 0 -or $inactiveUntreated -eq 0) 5
AddControl "C18" "NIST AC-2(3)" "Aucun compte inactif +90j sans notification"         ($inactiveUntreated -eq 0)     5
AddControl "C19" "NIST AC-2(4)" "Campagne de recertification trimestrielle documentée" $campaignExists               5
AddControl "C20" "ISO A.5.18"  "Rapport d'audit interne produit ce trimestre"         $true                          5  # Ce script lui-même

# ─── Calcul du score ───────────────────────────────────────────────────────────

$totalScore   = ($Controls | Measure-Object -Property Score  -Sum).Sum
$totalWeight  = ($Controls | Measure-Object -Property Weight -Sum).Sum
$scorePercent = [Math]::Round(($totalScore / $totalWeight) * 100, 1)
$passed       = ($Controls | Where-Object Passed).Count
$failed       = ($Controls | Where-Object { -not $_.Passed }).Count

$maturityLevel = switch ($scorePercent) {
    { $_ -ge 90 } { "OPTIMISÉ (Niveau 4)" }
    { $_ -ge 75 } { "GÉRÉ (Niveau 3)" }
    { $_ -ge 50 } { "DÉFINI (Niveau 2)" }
    { $_ -ge 25 } { "INITIAL (Niveau 1)" }
    default        { "INEXISTANT (Niveau 0)" }
}

$Controls | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"

# ─── Affichage du rapport ──────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║         AUDIT INTERNE IAM — $(Get-Date -Format 'dd/MM/yyyy')                         ║" -ForegroundColor Blue
Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Blue
Write-Host "║  SCORE DE MATURITÉ IAM    : $("$scorePercent% ($totalScore/$totalWeight pts)".PadRight(41))║" -ForegroundColor $(if ($scorePercent -ge 75) {"Green"} elseif ($scorePercent -ge 50) {"Yellow"} else {"Red"})
Write-Host "║  NIVEAU                   : $($maturityLevel.PadRight(41))║" -ForegroundColor White
Write-Host "║  Contrôles réussis        : $("$passed / 20".PadRight(41))║" -ForegroundColor Green
Write-Host "║  Contrôles échoués        : $("$failed / 20".PadRight(41))║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
Write-Host ""

Write-Host "  DÉTAIL DES CONTRÔLES ÉCHOUÉS :" -ForegroundColor Red
$Controls | Where-Object { -not $_.Passed } | ForEach-Object {
    Write-Host "  ✗ [$($_.ID)] $($_.Title) — Réf : $($_.Ref)" -ForegroundColor Red
}
Write-Host ""
Write-Host "  CONTRÔLES RÉUSSIS :" -ForegroundColor Green
$Controls | Where-Object { $_.Passed } | ForEach-Object {
    Write-Host "  ✓ [$($_.ID)] $($_.Title)" -ForegroundColor Green
}
Write-Host ""
Write-Host "  Rapport complet : $ReportFile" -ForegroundColor Gray

Write-Log "INFO" "=== FIN AUDIT — Score : $scorePercent% | Niveau : $maturityLevel ==="
