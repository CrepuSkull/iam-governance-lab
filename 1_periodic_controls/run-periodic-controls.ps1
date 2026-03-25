# run-periodic-controls.ps1
# Orchestrateur mensuel des contrôles périodiques IAM
# Pilote la séquence complète : notification → attente → désactivation → rapport
# Auteur : Arnaud MONTCHO — github.com/CrepuSkull
#
# USAGE :
#   Semaine 1 du mois → .\run-periodic-controls.ps1 -Phase Notify
#   Semaine 2 du mois → .\run-periodic-controls.ps1 -Phase Disable
#   En fin de mois    → .\run-periodic-controls.ps1 -Phase Report

[CmdletBinding()]
param(
    [ValidateSet("Notify","Disable","Report","Full")]
    [string]$Phase = "Full",
    [switch]$DryRun
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile   = "../logs/${timestamp}_orchestrator.log"
$null = New-Item -ItemType Directory -Force -Path "../logs"

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    $color = switch ($Level) { "INFO"{"Cyan"} "OK"{"Green"} "WARN"{"Yellow"} "HIGH"{"Red"} default{"White"} }
    Write-Host $line -ForegroundColor $color
}

Write-Log "INFO" "=== ORCHESTRATEUR CONTRÔLES PÉRIODIQUES === Phase : $Phase | $(if ($DryRun) {'SIMULATION'} else {'PRODUCTION'})"
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║  IAM GOVERNANCE LAB — Contrôles Périodiques Mensuels        ║" -ForegroundColor Blue
Write-Host "║  Date : $(Get-Date -Format 'dd/MM/yyyy HH:mm')                                    ║" -ForegroundColor Blue
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
Write-Host ""

switch ($Phase) {

    "Notify" {
        Write-Log "INFO" "--- PHASE 1 : NOTIFICATIONS J-7 ---"
        Write-Host "  → Envoi des alertes managers (comptes à désactiver dans 7 jours)" -ForegroundColor Cyan
        & ".\send-notifications.ps1" -SimulateEmail:$DryRun
        Write-Log "OK" "Notifications envoyées. Planifier disable-inactive.ps1 dans 7 jours."
        Write-Host ""
        Write-Host "  PROCHAINE ÉTAPE : Exécuter 'run-periodic-controls.ps1 -Phase Disable'" -ForegroundColor Yellow
        Write-Host "  DATE RECOMMANDÉE : $((Get-Date).AddDays(7).ToString('dd/MM/yyyy'))" -ForegroundColor Yellow
    }

    "Disable" {
        Write-Log "INFO" "--- PHASE 2 : DÉSACTIVATION COMPTES INACTIFS ---"
        Write-Host "  → Application du principe Silence vaut accord" -ForegroundColor Cyan
        & ".\disable-inactive.ps1" -DryRun:$DryRun
        Write-Log "OK" "Désactivation terminée. Surveiller les remontées (test du cri — 30 jours)."
        Write-Host ""
        Write-Host "  PROCHAINE ÉTAPE : Surveillance 30 jours puis suppression définitive" -ForegroundColor Yellow
    }

    "Report" {
        Write-Log "INFO" "--- PHASE 3 : RAPPORT DE SYNTHÈSE ---"
        Write-Host "  → Génération du rapport mensuel de gouvernance" -ForegroundColor Cyan

        $reports = Get-ChildItem -Path "../output" -Filter "disable_inactive_*.csv" |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($reports) {
            $data = Import-Csv -Path $reports.FullName -Delimiter ";"
            Write-Host ""
            Write-Host "  Rapport le plus récent : $($reports.Name)" -ForegroundColor Green
            Write-Host "  Comptes traités ce cycle : $($data.Count)" -ForegroundColor Green
            $data | Format-Table SamAccountName, DaysInactive, Action, PlannedDeletion -AutoSize
        } else {
            Write-Host "  Aucun rapport trouvé dans output/" -ForegroundColor Yellow
        }
    }

    "Full" {
        Write-Log "INFO" "--- MODE FULL : SÉQUENCE COMPLÈTE (lab uniquement) ---"
        Write-Host "  Mode Full : exécution de toutes les phases en simulation" -ForegroundColor Magenta
        Write-Host "  En production, utiliser -Phase Notify / Disable / Report séparément" -ForegroundColor Yellow
        Write-Host ""
        & ".\send-notifications.ps1" -SimulateEmail
        Write-Host ""
        & ".\disable-inactive.ps1" -DryRun
    }
}

Write-Log "INFO" "=== FIN ORCHESTRATEUR ==="
Write-Host ""
Write-Host "  Log complet : $LogFile" -ForegroundColor Gray
