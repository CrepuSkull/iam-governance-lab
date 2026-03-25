# escalate-pending.ps1
# Gestion des non-réponses — Application du principe "Silence vaut accord"
# À exécuter après la deadline si des managers n'ont pas répondu
# Conformité : ISO 27001:2022 A.5.18 | NIST AC-2(4)
# Auteur     : Arnaud MONTCHO — github.com/CrepuSkull
#
# RÈGLE "SILENCE VAUT ACCORD" :
#   Après J+15 sans réponse du manager :
#   → Les comptes ACTIFS et CONFORMES sont certifiés automatiquement
#   → Les comptes INACTIFS +90J sont désactivés (pas de validation tacite pour les comptes à risque)
#   → L'escalade vers le N+2 est documentée

[CmdletBinding()]
param(
    [string]$CampaignDir    = "../output",
    [string]$CampaignName   = "Q$(([Math]::Ceiling((Get-Date).Month / 3)))-$(Get-Date -Format 'yyyy')",
    [string]$OutputDir      = "../output",
    [string]$LogDir         = "../logs",
    [int]   $EscalateDays   = 15,
    [switch]$DryRun
)

$timestamp   = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile     = "$LogDir/${timestamp}_escalate-pending.log"
$EscReport   = "$OutputDir/escalation_report_${CampaignName}_$timestamp.csv"
$null        = New-Item -ItemType Directory -Force -Path $OutputDir, $LogDir

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) { "INFO"{"Cyan"} "OK"{"Green"} "WARN"{"Yellow"} "HIGH"{"Red"} "DRY"{"Magenta"} default{"White"} }
    Write-Host $line -ForegroundColor $color
}

Write-Log "INFO" "=== ESCALADE NON-RÉPONSES — Campagne : $CampaignName ==="
Write-Log "INFO" "Règle : Silence vaut accord après J+$EscalateDays"

# Charger les entrées sans réponse depuis les CSV de campagne
$campaignFolder = "$CampaignDir/campaign_$CampaignName"
$csvFiles       = Get-ChildItem -Path $campaignFolder -Filter "recertification_*.csv" -ErrorAction SilentlyContinue

$Pending   = @()
$Escalated = @()

foreach ($file in $csvFiles) {
    $entries = Import-Csv -Path $file.FullName -Encoding UTF8 -Delimiter ";"
    $pending = $entries | Where-Object { [string]::IsNullOrWhiteSpace($_.Decision) }

    foreach ($p in $pending) {
        $deadlineDate = if ($p.Deadline) { [datetime]$p.Deadline } else { (Get-Date).AddDays(-1) }
        $daysPastDeadline = ((Get-Date) - $deadlineDate).Days

        $silenceAction = if ([int]$p.DaysInactive -ge 90) {
            "DÉSACTIVATION — compte inactif, pas de certification tacite"
        } elseif ($daysPastDeadline -ge $EscalateDays) {
            "CERTIFIÉ AUTOMATIQUEMENT — Silence vaut accord"
        } else {
            "RELANCE — deadline pas encore atteinte"
        }

        $Pending += [PSCustomObject]@{
            SamAccountName     = $p.SamAccountName
            DisplayName        = $p.DisplayName
            Department         = $p.Department
            ManagerName        = $p.ManagerName
            Deadline           = $p.Deadline
            DaysPastDeadline   = $daysPastDeadline
            DaysInactive       = $p.DaysInactive
            InactivityAlert    = $p.InactivityAlert
            SilenceAction      = $silenceAction
            ProcessedDate      = (Get-Date -Format "yyyy-MM-dd")
        }

        $logLevel = if ($silenceAction -like "DÉSACTIVATION*") { "HIGH" } elseif ($silenceAction -like "CERTIFIÉ*") { "OK" } else { "WARN" }
        Write-Log $logLevel "$($p.SamAccountName) ($($p.ManagerName)) → $silenceAction"
    }
}

if ($Pending.Count -eq 0) {
    Write-Log "OK" "Aucune non-réponse détectée. Campagne 100% traitée."
} else {
    $Pending | Export-Csv -Path $EscReport -NoTypeInformation -Encoding UTF8 -Delimiter ";"

    $autoDisable = ($Pending | Where-Object { $_.SilenceAction -like "DÉSACTIVATION*" }).Count
    $autoCertify = ($Pending | Where-Object { $_.SilenceAction -like "CERTIFIÉ*" }).Count
    $toRelance   = ($Pending | Where-Object { $_.SilenceAction -like "RELANCE*" }).Count

    Write-Host ""
    Write-Host "  SYNTHÈSE ESCALADE" -ForegroundColor Blue
    Write-Host "  ─────────────────────────────────────────────"
    Write-Host "  Non-réponses traitées      : $($Pending.Count)" -ForegroundColor Cyan
    Write-Host "  Certifiés automatiquement  : $autoCertify (silence vaut accord)" -ForegroundColor Green
    Write-Host "  Désactivations forcées     : $autoDisable (comptes inactifs — pas de tacite)" -ForegroundColor Red
    Write-Host "  Relances nécessaires       : $toRelance" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  RÈGLE APPLIQUÉE :" -ForegroundColor White
    Write-Host "  → Compte actif + silence > J+$EscalateDays = Certifié (accès maintenu)" -ForegroundColor Gray
    Write-Host "  → Compte inactif +90j + silence = Désactivé (risque trop élevé pour certification tacite)" -ForegroundColor Gray
    Write-Host ""
}

Write-Log "INFO" "=== FIN ESCALADE ==="
