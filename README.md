# IAM Governance Lab

> Contrôle continu, campagnes de recertification et audit interne IAM.  
> Ce lab couvre la couche **IGA (Identity Governance & Administration)** :  
> non pas créer ou supprimer des comptes, mais **prouver en permanence que les accès sont légitimes**.

Méthodologie : ISO 27001:2022 · NIST SP 800-53 · Principe "Silence vaut accord"

---

## Positionnement dans l'écosystème

```
iam-foundation-lab              → Audit AD ponctuel + migration Entra ID
IAM-Lab-Identity-Lifecycle      → Opérations JML quotidiennes (Joiner/Mover/Leaver)
iam-governance-lab  ◄ CE REPO  → Contrôle continu + preuves d'audit périodiques
```

La gouvernance ne remplace pas les opérations — elle les supervise.  
Un Leaver traité via `leaver.ps1` produit un événement.  
Ce repo s'assure que cet événement est **mesuré, certifié et documenté** pour l'auditeur.

---

## Modules

| Module | Dossier | Objectif |
|--------|---------|----------|
| **Contrôles périodiques** | `1_periodic_controls/` | Désactivation automatique J+90, relances, rapport d'exclusions |
| **Campagne de recertification** | `2_recertification/` | Générer les listes manager, tracer les validations/révocations |
| **Audit interne IAM** | `3_internal_audit/` | Checklist ISO 27001 A.5.18 + rapport scoré |

---

## Architecture

```
iam-governance-lab/
├── data/
│   ├── employees.csv              ← Source RH autoritaire
│   ├── exclusions.csv             ← Comptes exemptés des contrôles automatiques
│   └── recertification_results/   ← Réponses managers importées
├── 1_periodic_controls/
│   ├── run-periodic-controls.ps1  ← Orchestrateur mensuel
│   ├── disable-inactive.ps1       ← Désactivation J+90 avec délais incompressibles
│   ├── send-notifications.ps1     ← Alertes J-7 avant désactivation
│   └── README.md
├── 2_recertification/
│   ├── generate-campaign.ps1      ← Génère les listes par manager
│   ├── process-responses.ps1      ← Traite les retours (valider / révoquer)
│   ├── escalate-pending.ps1       ← Relances (silence vaut accord J+15)
│   └── README.md
├── 3_internal_audit/
│   ├── run-audit.ps1              ← Audit scoré sur 20 contrôles
│   ├── audit-checklist.md         ← Référentiel des 20 contrôles ISO/NIST
│   └── README.md
├── output/
├── logs/
└── docs/
    ├── governance-framework.md    ← Cadre applicable à toute structure
    ├── delays-calendar.md         ← Délais incompressibles documentés
    └── exclusion-criteria.md      ← Critères de la whitelist
```

---

## Principe fondateur : les délais incompressibles

Un contrôle IAM brutal casse la production. Ce lab intègre les délais terrain :

```
J0   → Compte détecté inactif (+90 jours sans connexion)
J0   → Alerte envoyée au manager ("Ce compte sera désactivé dans 7 jours")
J+7  → Si aucune réponse : désactivation (Silence vaut accord)
J+7  → Compte déplacé en OU Quarantine (données conservées)
J+37 → Test du cri : si aucune remontée, suppression planifiée
J+90 → Suppression définitive (conformité RGPD — rétention 90 jours)
```

---

## Démarrage rapide

```powershell
# Contrôles périodiques (mensuel recommandé)
.\1_periodic_controls\run-periodic-controls.ps1

# Campagne de recertification trimestrielle
.\2_recertification\generate-campaign.ps1
.\2_recertification\process-responses.ps1
.\2_recertification\escalate-pending.ps1

# Audit interne IAM
.\3_internal_audit\run-audit.ps1
```

---

## Ce que l'auditeur voit

| Question auditeur | Livrable généré |
|-------------------|-----------------------------|
| *"Comment gérez-vous les comptes inactifs ?"* | Rapport disable-inactive + log horodaté |
| *"Les managers valident-ils les accès ?"* | Rapport campagne + preuve de réponse |
| *"Que se passe-t-il si un manager ne répond pas ?"* | Log escalade + règle silence-vaut-accord documentée |
| *"Pouvez-vous scorer votre maturité IAM ?"* | Rapport audit scoré sur 100 |
| *"Quels comptes sont exemptés et pourquoi ?"* | exclusions.csv + exclusion-criteria.md |

---

*Auteur : Arnaud MONTCHO — Consultant IAM/IGA — github.com/CrepuSkull*
