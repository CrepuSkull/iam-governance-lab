# generate-campaign.ps1
# Génération d'une campagne de recertification des accès
# Produit les listes par manager pour validation trimestrielle
# Conformité : ISO 27001:2022 A.5.18 | NIST AC-2(4)
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull
#
# PROCESSUS DE RECERTIFICATION :
#
#   Étape 1 : generate-campaign.ps1   → Génère les listes par manager (ce script)
#   Étape 2 : Distribution aux managers (email, SharePoint, outil GRC...)
#   Étape 3 : Managers renseignent la colonne Decision (Certifié / Révoquer / Exception)
#   Étape 4 : process-responses.ps1   → Traite les retours
#   Étape 5 : escalate-pending.ps1    → Relances et silence vaut accord J+15

[CmdletBinding()]
param(
    [string]$HRSourceFile   = "../data/employees.csv",
    [string]$ExclusionsFile = "../data/exclusions.csv",
    [string]$ADSnapshotFile = "../data/ad_snapshot.csv",
    [string]$OutputDir      = "../output",
    [string]$LogDir         = "../logs",
    [string]$CampaignName   = "Q$(([Math]::Ceiling((Get-Date).Month / 3)))-$(Get-Date -Format 'yyyy')",
    [int]   $ResponseDeadlineDays = 15
)

$timestamp      = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile        = "$LogDir/${timestamp}_generate-campaign.log"
$CampaignDir    = "$OutputDir/campaign_$CampaignName"
$SummaryFile    = "$CampaignDir/campaign_summary_$CampaignName.txt"

$null = New-Item -ItemType Directory -Force -Path $CampaignDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) { "INFO"{"Cyan"} "OK"{"Green"} "WARN"{"Yellow"} default{"White"} }
    Write-Host $line -ForegroundColor $color
}

$now          = Get-Date
$Deadline     = $now.AddDays($ResponseDeadlineDays)
$SilenceDate  = $now.AddDays($ResponseDeadlineDays)  # Silence vaut accord = deadline

Write-Log "INFO" "=== GÉNÉRATION CAMPAGNE RECERTIFICATION : $CampaignName ==="
Write-Log "INFO" "Deadline réponse : $($Deadline.ToString('dd/MM/yyyy')) (J+$ResponseDeadlineDays)"
Write-Log "INFO" "Principe Silence vaut accord appliqué à J+$ResponseDeadlineDays"

# ─── Chargement des données ────────────────────────────────────────────────────

$HRList = Import-Csv -Path $HRSourceFile -Encoding UTF8
$HRById = @{}
foreach ($hr in $HRList) { $HRById[$hr.EmployeeID] = $hr }

$Exclusions = @{}
if (Test-Path $ExclusionsFile) {
    $excList = Import-Csv -Path $ExclusionsFile -Encoding UTF8
    foreach ($ex in $excList) { $Exclusions[$ex.SamAccountName] = $ex }
}

# Snapshot AD simulé si non disponible
$now2 = Get-Date
$ADUsers = if (Test-Path $ADSnapshotFile) {
    Import-Csv -Path $ADSnapshotFile -Encoding UTF8
} else {
    @(
        [PSCustomObject]@{ SamAccountName="jdupont";   DisplayName="Jean Dupont";      Enabled="True"; LastLogonDate=$now2.AddDays(-5);  Department="Finance"; EmployeeID="E001"; ManagerID="E005"; MemberOf="GRP_FINANCE_USERS" }
        [PSCustomObject]@{ SamAccountName="lmoreau";   DisplayName="Lucie Moreau";     Enabled="True"; LastLogonDate=$now2.AddDays(-3);  Department="Finance"; EmployeeID="E008"; ManagerID="E001"; MemberOf="GRP_FINANCE_USERS" }
        [PSCustomObject]@{ SamAccountName="slefebvre"; DisplayName="Sarah Lefebvre";   Enabled="True"; LastLogonDate=$now2.AddDays(-2);  Department="IT";      EmployeeID="E002"; ManagerID="E005"; MemberOf="GRP_IT_USERS" }
        [PSCustomObject]@{ SamAccountName="pduval";    DisplayName="Pierre Duval";     Enabled="True"; LastLogonDate=$now2.AddDays(-110);Department="IT";      EmployeeID="E009"; ManagerID="E002"; MemberOf="GRP_IT_USERS" }
        [PSCustomObject]@{ SamAccountName="amartin";   DisplayName="Arnaud Martin";    Enabled="True"; LastLogonDate=$now2.AddDays(-1);  Department="RH";      EmployeeID="E003"; ManagerID="E005"; MemberOf="GRP_RH_USERS" }
        [PSCustomObject]@{ SamAccountName="aleclerc";  DisplayName="Ambre Leclerc";    Enabled="True"; LastLogonDate=$now2.AddDays(-4);  Department="RH";      EmployeeID="E010"; ManagerID="E003"; MemberOf="GRP_RH_USERS" }
        [PSCustomObject]@{ SamAccountName="mlaurent";  DisplayName="Michel Laurent";   Enabled="True"; LastLogonDate=$now2.AddDays(-1);  Department="IT";      EmployeeID="E005"; ManagerID="";     MemberOf="GRP_IT_USERS;GRP_IT_ADMINS" }
        [PSCustomObject]@{ SamAccountName="svc_backup";DisplayName="Service Backup";   Enabled="True"; LastLogonDate=$now2.AddDays(-180);Department="IT";      EmployeeID="";     ManagerID="E005"; MemberOf="GRP_IT_ADMINS" }
    )
}

Write-Log "INFO" "Comptes à certifier : $($ADUsers.Count) | Exemptions : $($Exclusions.Count)"

# ─── Regroupement par manager ──────────────────────────────────────────────────

$ByManager = @{}

foreach ($User in $ADUsers) {

    if ($User.Enabled -ne "True") { continue }
    if ($Exclusions.ContainsKey($User.SamAccountName)) {
        Write-Log "INFO" "Exempté de la campagne : $($User.SamAccountName)"
        continue
    }

    $managerKey   = if ($User.ManagerID) { $User.ManagerID } else { "_NO_MANAGER_" }
    $managerName  = "MANAGER INCONNU"
    $managerEmail = "it-security@lab.local"

    if ($User.ManagerID -and $HRById.ContainsKey($User.ManagerID)) {
        $mgr = $HRById[$User.ManagerID]
        $managerName  = "$($mgr.FirstName) $($mgr.LastName)"
        $managerEmail = "$($mgr.FirstName.Substring(0,1).ToLower())$($mgr.LastName.ToLower())@lab.local"
    }

    if (-not $ByManager.ContainsKey($managerKey)) {
        $ByManager[$managerKey] = @{
            ManagerName  = $managerName
            ManagerEmail = $managerEmail
            Users        = @()
        }
    }

    $lastLogon    = if ($User.LastLogonDate) { [datetime]$User.LastLogonDate } else { $null }
    $daysInactive = if ($lastLogon) { ($now - $lastLogon).Days } else { 9999 }

    $ByManager[$managerKey].Users += [PSCustomObject]@{
        # Colonnes d'information (lecture seule pour le manager)
        CampaignID          = $CampaignName
        SamAccountName      = $User.SamAccountName
        DisplayName         = $User.DisplayName
        Department          = $User.Department
        EmployeeID          = $User.EmployeeID
        CurrentGroups       = $User.MemberOf
        LastLogonDate       = if ($lastLogon) { $lastLogon.ToString("yyyy-MM-dd") } else { "Jamais" }
        DaysInactive        = $daysInactive
        InactivityAlert     = if ($daysInactive -ge 90) { "⚠ INACTIF +90J" } elseif ($daysInactive -ge 45) { "Attention +45J" } else { "OK" }
        # Colonnes à remplir par le manager
        Decision            = ""   # Certifié | Révoquer | Exception
        JustificationRevoke = ""   # Obligatoire si Decision = Révoquer
        JustificationException = "" # Obligatoire si Decision = Exception
        ManagerName         = $managerName
        Deadline            = $Deadline.ToString("yyyy-MM-dd")
    }
}

# ─── Génération des fichiers par manager ──────────────────────────────────────

$totalUsers  = 0
$totalManagers = 0

foreach ($mgrKey in $ByManager.Keys) {
    $mgrData  = $ByManager[$mgrKey]
    $mgrSafe  = $mgrData.ManagerName -replace "[^a-zA-Z0-9]", "_"
    $csvFile  = "$CampaignDir/recertification_${CampaignName}_${mgrSafe}.csv"

    $mgrData.Users | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"

    Write-Log "OK" "Fichier généré pour $($mgrData.ManagerName) : $($mgrData.Users.Count) compte(s) — $($mgrData.ManagerEmail)"
    $totalUsers    += $mgrData.Users.Count
    $totalManagers++
}

# ─── Résumé de campagne ────────────────────────────────────────────────────────

$summary = @"
╔══════════════════════════════════════════════════════════════════════╗
║    CAMPAGNE DE RECERTIFICATION : $($CampaignName.PadRight(33))║
║    Générée le : $(Get-Date -Format 'dd/MM/yyyy HH:mm')                               ║
╠══════════════════════════════════════════════════════════════════════╣
║  Managers concernés      : $($totalManagers.ToString().PadRight(38))║
║  Comptes à certifier     : $($totalUsers.ToString().PadRight(38))║
║  Deadline de réponse     : $($Deadline.ToString('dd/MM/yyyy').PadRight(38))║
║  Silence vaut accord le  : $($SilenceDate.ToString('dd/MM/yyyy').PadRight(38))║
╠══════════════════════════════════════════════════════════════════════╣
║  Dossier campagne        : campaign_$($CampaignName.PadRight(32))║
╚══════════════════════════════════════════════════════════════════════╝

INSTRUCTIONS POUR LES MANAGERS :
  1. Ouvrir votre fichier CSV personnalisé
  2. Pour chaque compte, renseigner la colonne "Decision" :
       → "Certifié"   : L'accès est légitime et maintenu
       → "Révoquer"   : L'accès doit être supprimé (remplir JustificationRevoke)
       → "Exception"  : Cas particulier à traiter manuellement (remplir JustificationException)
  3. Retourner le fichier complété avant le $($Deadline.ToString('dd/MM/yyyy'))
  4. Sans réponse : le compte sera certifié automatiquement (Silence vaut accord)
     SAUF si le compte est marqué ⚠ INACTIF +90J : il sera désactivé

CONFORMITÉ :
  ISO 27001:2022 A.5.18 — Revue périodique des droits d'accès
  NIST SP 800-53 AC-2(4) — Revue automatisée de la gestion des comptes
"@

Set-Content -Path $SummaryFile -Value $summary -Encoding UTF8
Write-Host $summary
Write-Log "INFO" "=== FIN GÉNÉRATION CAMPAGNE — $totalManagers managers / $totalUsers comptes ==="
Write-Log "INFO" "Dossier : $CampaignDir"
Write-Log "INFO" "Prochaine étape : distribuer les CSV aux managers, puis exécuter process-responses.ps1"
