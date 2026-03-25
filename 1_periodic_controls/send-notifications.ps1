# send-notifications.ps1
# Envoi des alertes J-7 avant désactivation des comptes inactifs
# À exécuter 7 jours AVANT disable-inactive.ps1
# Conformité : ISO 27001:2022 A.5.18 | NIST AC-2(3)
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull
#
# Ce script génère les alertes "Silence vaut accord" :
#   → Notifie le manager qu'un compte de son équipe sera désactivé dans 7 jours
#   → Si aucune réponse dans 7 jours : disable-inactive.ps1 procède à la désactivation
#   → Journal des notifications = preuve pour l'auditeur

[CmdletBinding()]
param(
    [string]$HRSourceFile   = "../data/employees.csv",
    [string]$ExclusionsFile = "../data/exclusions.csv",
    [string]$ADSnapshotFile = "../data/ad_snapshot.csv",
    [string]$OutputDir      = "../output",
    [string]$LogDir         = "../logs",
    [int]   $InactivityDays = 90,
    [switch]$SimulateEmail          # $true = afficher sans envoyer (lab)
)

$timestamp    = Get-Date -Format "yyyyMMdd_HHmm"
$NotifLog     = "$LogDir/notifications_sent.csv"   # Partagé avec disable-inactive.ps1
$NotifReport  = "$OutputDir/notifications_report_$timestamp.csv"
$LogFile      = "$LogDir/${timestamp}_send-notifications.log"

$null = New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) { "INFO"{"Cyan"} "OK"{"Green"} "WARN"{"Yellow"} "SIM"{"Magenta"} default{"White"} }
    Write-Host $line -ForegroundColor $color
}

Write-Log "INFO" "=== NOTIFICATIONS J-7 — Seuil inactivité : $InactivityDays jours ==="

$Exclusions = @{}
if (Test-Path $ExclusionsFile) {
    $excList = Import-Csv -Path $ExclusionsFile -Encoding UTF8
    foreach ($ex in $excList) { $Exclusions[$ex.SamAccountName] = $ex }
}

$HRManagers = @{}
if (Test-Path $HRSourceFile) {
    $hrList = Import-Csv -Path $HRSourceFile -Encoding UTF8
    foreach ($hr in $hrList) { $HRManagers[$hr.EmployeeID] = $hr }
}

# Snapshot AD simulé
$now = Get-Date
$ThresholdDate = $now.AddDays(-$InactivityDays)
$DisableDate   = $now.AddDays(7)

$ADUsers = if (Test-Path $ADSnapshotFile) {
    Import-Csv -Path $ADSnapshotFile -Encoding UTF8
} else {
    @(
        [PSCustomObject]@{ SamAccountName="trenard";     DisplayName="Thomas Renard";      Enabled="True"; LastLogonDate=$now.AddDays(-95);  Department="IT";      EmployeeID="E007"; ManagerID="E005" }
        [PSCustomObject]@{ SamAccountName="pduval";      DisplayName="Pierre Duval";       Enabled="True"; LastLogonDate=$now.AddDays(-110); Department="IT";      EmployeeID="E009"; ManagerID="E002" }
        [PSCustomObject]@{ SamAccountName="smoreau_old"; DisplayName="Sophie Moreau (old)";Enabled="True"; LastLogonDate=$now.AddDays(-200); Department="Finance"; EmployeeID="";     ManagerID="E001" }
    )
}

$Notifications = @()
$sent = 0

foreach ($User in $ADUsers) {
    if ($User.Enabled -ne "True") { continue }
    if ($Exclusions.ContainsKey($User.SamAccountName)) { continue }

    $lastLogon = if ($User.LastLogonDate) { [datetime]$User.LastLogonDate } else { $null }
    $daysInactive = if ($lastLogon) { ($now - $lastLogon).Days } else { 9999 }
    if ($daysInactive -lt $InactivityDays) { continue }

    # Récupération du manager
    $managerName  = "Manager inconnu"
    $managerEmail = "it-security@lab.local"
    if ($User.ManagerID -and $HRManagers.ContainsKey($User.ManagerID)) {
        $mgr = $HRManagers[$User.ManagerID]
        $managerName  = "$($mgr.FirstName) $($mgr.LastName)"
        $managerEmail = "$($mgr.FirstName.Substring(0,1).ToLower())$($mgr.LastName.ToLower())@lab.local"
    }

    # Génération du message (simulé en lab)
    $emailBody = @"
Objet : [IAM] Action requise — Compte inactif détecté dans votre équipe

Bonjour $managerName,

Dans le cadre de notre politique de gouvernance des accès (ISO 27001 A.5.18),
nous avons détecté le compte suivant inactif depuis plus de $InactivityDays jours :

  Compte      : $($User.SamAccountName)
  Utilisateur : $($User.DisplayName)
  Département : $($User.Department)
  Dernière connexion : $(if ($lastLogon) { $lastLogon.ToString('dd/MM/yyyy') } else { 'Jamais' })
  Jours d'inactivité : $daysInactive jours

ACTION REQUISE avant le $($DisableDate.ToString('dd/MM/yyyy')) :
  → Si ce compte est toujours nécessaire, répondez à ce message avec la justification.
  → Sans réponse de votre part, le compte sera désactivé automatiquement.
     (Principe "Silence vaut accord" — Politique IAM §4.2)

En cas de désactivation, les données sont conservées 90 jours avant suppression.

Équipe Sécurité IT
"@

    if ($SimulateEmail) {
        Write-Log "SIM" "EMAIL SIMULÉ → $managerEmail"
        Write-Host $emailBody -ForegroundColor Gray
    } else {
        # En production : Send-MailMessage ou Graph API
        # Send-MailMessage -To $managerEmail -Subject "[IAM] Action requise — Compte inactif" -Body $emailBody -SmtpServer "smtp.lab.local"
        Write-Log "OK" "Notification envoyée : $($User.SamAccountName) → Manager : $managerName ($managerEmail)"
    }

    $Notifications += [PSCustomObject]@{
        SamAccountName    = $User.SamAccountName
        DisplayName       = $User.DisplayName
        Department        = $User.Department
        DaysInactive      = $daysInactive
        LastLogonDate     = if ($lastLogon) { $lastLogon.ToString("yyyy-MM-dd") } else { "Jamais" }
        ManagerName       = $managerName
        ManagerEmail      = $managerEmail
        NotificationDate  = $now.ToString("yyyy-MM-dd")
        DisableIfNoReply  = $DisableDate.ToString("yyyy-MM-dd")
        Status            = "NOTIFIÉ"
    }
    $sent++
}

# Export — ce fichier est lu par disable-inactive.ps1
$Notifications | Export-Csv -Path $NotifLog    -NoTypeInformation -Encoding UTF8 -Delimiter ";" -Append
$Notifications | Export-Csv -Path $NotifReport -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Log "INFO" "=== FIN NOTIFICATIONS — $sent alerte(s) envoyée(s) ==="
Write-Log "INFO" "Journal mis à jour : $NotifLog"
Write-Log "INFO" "Prochaine étape : exécuter disable-inactive.ps1 dans $($DisableDate - $now | Select-Object -ExpandProperty Days) jours"
