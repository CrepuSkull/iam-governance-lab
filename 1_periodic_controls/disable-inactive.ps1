# disable-inactive.ps1
# Désactivation des comptes inactifs avec délais incompressibles et whitelist d'exclusions
# Conformité : ISO 27001:2022 A.5.18 | NIST SP 800-53 AC-2(3) | RGPD Art. 5(1)(e)
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull
#
# CYCLE DE VIE D'UN COMPTE INACTIF (délais incompressibles) :
#
#   J0    → Détection inactivité > $InactivityDays jours
#   J0    → Alerte manager (send-notifications.ps1)
#   J+7   → Désactivation si aucune réponse (Silence vaut accord)
#   J+7   → Déplacement OU Quarantine
#   J+37  → "Test du cri" — fenêtre de 30 jours pour remontées
#   J+90  → Suppression planifiée (rétention RGPD)
#
# Ce script gère l'étape J+7 : désactivation et quarantaine.
# Il requiert que send-notifications.ps1 ait été exécuté 7 jours avant.

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$HRSourceFile    = "../data/employees.csv",
    [string]$ExclusionsFile  = "../data/exclusions.csv",
    [string]$ADSnapshotFile  = "../data/ad_snapshot.csv",
    [string]$NotifLogFile    = "../logs/notifications_sent.csv",  # Produit par send-notifications.ps1
    [string]$OutputDir       = "../output",
    [string]$LogDir          = "../logs",
    [int]   $InactivityDays  = 90,
    [int]   $GracePeriodDays = 7,        # Délai après notification avant désactivation
    [int]   $RetentionDays   = 90,       # Durée quarantaine avant suppression
    [string]$DomainDN        = "DC=lab,DC=local",
    [string]$QuarantineOU    = "OU=Quarantine,OU=Disabled",
    [switch]$DryRun                      # Simulation sans modification — toujours tester d'abord
)

# ─── Initialisation ────────────────────────────────────────────────────────────

$timestamp   = Get-Date -Format "yyyyMMdd_HHmm"
$ReportFile  = "$OutputDir/disable_inactive_$timestamp.csv"
$ExclusionReport = "$OutputDir/exclusions_report_$timestamp.csv"
$LogFile     = "$LogDir/${timestamp}_disable-inactive.log"

$null = New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) {
        "INFO"  {"Cyan"} "OK" {"Green"} "WARN" {"Yellow"}
        "HIGH"  {"Red"}  "DRY" {"Magenta"} default {"White"}
    }
    Write-Host $line -ForegroundColor $color
}

$mode = if ($DryRun) { "SIMULATION (DryRun)" } else { "PRODUCTION" }
Write-Log "INFO" "=== CONTRÔLE PÉRIODIQUE — COMPTES INACTIFS === Mode : $mode"
Write-Log "INFO" "Seuil inactivité : $InactivityDays jours | Délai grâce : $GracePeriodDays jours"
Write-Log "INFO" "Rétention quarantaine : $RetentionDays jours"

# ─── Chargement des sources ────────────────────────────────────────────────────

# Whitelist d'exclusions
$Exclusions = @{}
if (Test-Path $ExclusionsFile) {
    $excList = Import-Csv -Path $ExclusionsFile -Encoding UTF8
    foreach ($ex in $excList) { $Exclusions[$ex.SamAccountName] = $ex }
    Write-Log "INFO" "Whitelist chargée : $($Exclusions.Count) comptes exemptés"
} else {
    Write-Log "WARN" "Fichier d'exclusions introuvable — aucune exemption appliquée"
}

# Source RH
$HRData = @{}
if (Test-Path $HRSourceFile) {
    $hrList = Import-Csv -Path $HRSourceFile -Encoding UTF8
    foreach ($hr in $hrList) { $HRData[$hr.EmployeeID] = $hr }
}

# Journal des notifications envoyées (J-7)
$NotifiedAccounts = @{}
if (Test-Path $NotifLogFile) {
    $notifs = Import-Csv -Path $NotifLogFile -Encoding UTF8
    foreach ($n in $notifs) { $NotifiedAccounts[$n.SamAccountName] = $n }
    Write-Log "INFO" "Notifications précédentes : $($NotifiedAccounts.Count) comptes"
} else {
    Write-Log "WARN" "Aucun journal de notifications trouvé — le délai de grâce ne sera pas appliqué"
}

# ─── Données AD (simulées en lab) ─────────────────────────────────────────────

$now = Get-Date
$ThresholdDate = $now.AddDays(-$InactivityDays)
$DeleteDate    = $now.AddDays($RetentionDays)

if (Test-Path $ADSnapshotFile) {
    $ADUsers = Import-Csv -Path $ADSnapshotFile -Encoding UTF8
} else {
    Write-Log "WARN" "Snapshot AD non trouvé. Génération d'un jeu simulé."
    $ADUsers = @(
        [PSCustomObject]@{ SamAccountName="jdupont";     DisplayName="Jean Dupont";       Enabled="True";  LastLogonDate=$now.AddDays(-5);   Department="Finance"; EmployeeID="E001"; MemberOf="GRP_FINANCE_USERS" }
        [PSCustomObject]@{ SamAccountName="slefebvre";   DisplayName="Sarah Lefebvre";    Enabled="True";  LastLogonDate=$now.AddDays(-3);   Department="IT";      EmployeeID="E002"; MemberOf="GRP_IT_USERS" }
        [PSCustomObject]@{ SamAccountName="trenard";     DisplayName="Thomas Renard";     Enabled="True";  LastLogonDate=$now.AddDays(-95);  Department="IT";      EmployeeID="E007"; MemberOf="GRP_IT_USERS" }
        [PSCustomObject]@{ SamAccountName="pduval";      DisplayName="Pierre Duval";      Enabled="True";  LastLogonDate=$now.AddDays(-110); Department="IT";      EmployeeID="E009"; MemberOf="GRP_IT_USERS" }
        [PSCustomObject]@{ SamAccountName="smoreau_old"; DisplayName="Sophie Moreau old"; Enabled="True";  LastLogonDate=$now.AddDays(-200); Department="Finance"; EmployeeID="";     MemberOf="GRP_FINANCE_USERS" }
        [PSCustomObject]@{ SamAccountName="svc_backup";  DisplayName="Service Backup";    Enabled="True";  LastLogonDate=$now.AddDays(-180); Department="IT";      EmployeeID="";     MemberOf="GRP_IT_ADMINS" }
        [PSCustomObject]@{ SamAccountName="cfontaine";   DisplayName="Christine Fontaine";Enabled="True";  LastLogonDate=$now.AddDays(-95);  Department="Finance"; EmployeeID="E011"; MemberOf="GRP_FINANCE_USERS" }
    )
}

# ─── Analyse et décision par compte ───────────────────────────────────────────

$ToDisable   = @()
$ExcludedLog = @()
$Results     = @()

foreach ($User in $ADUsers) {

    if ($User.Enabled -ne "True") { continue }  # Déjà désactivé

    $lastLogon = if ($User.LastLogonDate) { [datetime]$User.LastLogonDate } else { $null }
    $daysInactive = if ($lastLogon) { ($now - $lastLogon).Days } else { 9999 }
    $isInactive = $daysInactive -ge $InactivityDays

    if (-not $isInactive) { continue }  # Pas de problème

    # ── Vérification whitelist ─────────────────────────────────────────────────
    if ($Exclusions.ContainsKey($User.SamAccountName)) {
        $ex = $Exclusions[$User.SamAccountName]

        # Vérifier si l'exemption est expirée
        $reviewDate = if ($ex.ReviewDate) { [datetime]$ex.ReviewDate } else { $now.AddDays(1) }
        if ($now -gt $reviewDate) {
            Write-Log "WARN" "EXEMPTION EXPIRÉE : $($User.SamAccountName) — ReviewDate : $($ex.ReviewDate) — traité comme compte normal"
        } else {
            $ExcludedLog += [PSCustomObject]@{
                SamAccountName  = $User.SamAccountName
                DisplayName     = $User.DisplayName
                DaysInactive    = $daysInactive
                ExclusionType   = $ex.ExclusionType
                Reason          = $ex.Reason
                ReviewDate      = $ex.ReviewDate
                AuditDate       = $now.ToString("yyyy-MM-dd")
            }
            Write-Log "INFO" "EXEMPTÉ : $($User.SamAccountName) [$($ex.ExclusionType)] — $($ex.Reason)"
            continue
        }
    }

    # ── Vérification délai de grâce (notification envoyée il y a 7+ jours ?) ──
    $gracePassed = $true
    if ($NotifiedAccounts.ContainsKey($User.SamAccountName)) {
        $notifDate = [datetime]$NotifiedAccounts[$User.SamAccountName].NotificationDate
        $daysSinceNotif = ($now - $notifDate).Days
        if ($daysSinceNotif -lt $GracePeriodDays) {
            $gracePassed = $false
            Write-Log "WARN" "DÉLAI GRÂCE EN COURS : $($User.SamAccountName) — Notifié il y a $daysSinceNotif jours (attente $GracePeriodDays jours)"
        }
    } else {
        # Pas de notification trouvée — ajouter à la liste pour notification J+0
        Write-Log "WARN" "NOTIFICATION MANQUANTE : $($User.SamAccountName) — À notifier avant désactivation (run send-notifications.ps1)"
        $gracePassed = $false
    }

    if (-not $gracePassed) { continue }

    # ── Désactivation ──────────────────────────────────────────────────────────
    $ToDisable += $User

    $action = if ($DryRun) { "SIMULATION" } else { "DÉSACTIVÉ" }
    $entry = [PSCustomObject]@{
        SamAccountName   = $User.SamAccountName
        DisplayName      = $User.DisplayName
        Department       = $User.Department
        EmployeeID       = $User.EmployeeID
        DaysInactive     = $daysInactive
        LastLogonDate    = if ($lastLogon) { $lastLogon.ToString("yyyy-MM-dd") } else { "Jamais" }
        Action           = $action
        QuarantineOU     = "$QuarantineOU,$DomainDN"
        PlannedDeletion  = $DeleteDate.ToString("yyyy-MM-dd")
        Operator         = $env:USERNAME
        ExecutionDate    = $now.ToString("yyyy-MM-dd")
    }
    $Results += $entry

    if ($DryRun) {
        Write-Log "DRY" "SIMULATION désactivation : $($User.SamAccountName) (inactif $daysInactive jours) → Suppression planifiée $($DeleteDate.ToString('yyyy-MM-dd'))"
    } else {
        # En production AD réel : décommenter ces lignes
        # Disable-ADAccount -Identity $User.SamAccountName
        # Move-ADObject -Identity $User.DistinguishedName -TargetPath "$QuarantineOU,$DomainDN"
        # Set-ADUser -Identity $User.SamAccountName -Description "LEAVER - Désactivé $(Get-Date -Format 'yyyy-MM-dd') - Suppression $($DeleteDate.ToString('yyyy-MM-dd'))"
        Write-Log "OK" "DÉSACTIVÉ : $($User.SamAccountName) (inactif $daysInactive jours) → Quarantaine jusqu'au $($DeleteDate.ToString('yyyy-MM-dd'))"
    }
}

# ─── Export rapports ───────────────────────────────────────────────────────────

$Results     | Export-Csv -Path $ReportFile       -NoTypeInformation -Encoding UTF8 -Delimiter ";"
$ExcludedLog | Export-Csv -Path $ExclusionReport  -NoTypeInformation -Encoding UTF8 -Delimiter ";"

# ─── Résumé exécutif ───────────────────────────────────────────────────────────

$summary = @"

╔══════════════════════════════════════════════════════════════════════╗
║    CONTRÔLE PÉRIODIQUE — COMPTES INACTIFS — $(Get-Date -Format 'dd/MM/yyyy')          ║
║    Mode : $($mode.PadRight(55))║
╠══════════════════════════════════════════════════════════════════════╣
║  Comptes analysés             : $($ADUsers.Count.ToString().PadRight(35))║
║  Inactifs détectés (+$InactivityDays jours)    : $(($ToDisable.Count + $ExcludedLog.Count).ToString().PadRight(35))║
║  Exemptés (whitelist)         : $($ExcludedLog.Count.ToString().PadRight(35))║
║  Désactivés (ou simulés)      : $($ToDisable.Count.ToString().PadRight(35))║
╠══════════════════════════════════════════════════════════════════════╣
║  Suppression planifiée après  : $($DeleteDate.ToString('yyyy-MM-dd').PadRight(35))║
╠══════════════════════════════════════════════════════════════════════╣
║  Rapport actions              : $($ReportFile.Split('/')[-1].PadRight(35))║
║  Rapport exemptions           : $($ExclusionReport.Split('/')[-1].PadRight(35))║
╚══════════════════════════════════════════════════════════════════════╝

RAPPELS OPÉRATIONNELS :
  → Vérifier les systèmes NON-AD (VPN, SaaS, badges physiques, messagerie)
  → Conserver les boîtes mail 30 jours pour passation de dossiers
  → Revoir les exemptions expirées avant le prochain cycle
"@

Write-Host $summary
Write-Log "INFO" "=== FIN — Désactivés : $($ToDisable.Count) | Exemptés : $($ExcludedLog.Count) ==="
if ($DryRun) { Write-Log "DRY" "Mode simulation — aucune modification appliquée. Relancer sans -DryRun pour appliquer." }
