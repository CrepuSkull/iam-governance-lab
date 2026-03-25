# Critères d'Exclusion — Whitelist des contrôles automatiques

> Ce document définit les catégories de comptes exemptés des contrôles automatiques  
> et les conditions d'exemption. Toute exemption doit être documentée, justifiée  
> et soumise à revue périodique.

---

## Principe général

Un contrôle IAM non filtré désactive des comptes critiques.  
La whitelist n'est pas une faille — c'est une **maîtrise consciente du risque**.  
Chaque exemption doit répondre à la question : *"Pourquoi ce compte ne suit-il pas le processus standard ?"*

---

## Catégories d'exemption

### Type 1 — ServiceAccount
Comptes utilisés par des applications ou processus automatisés.  
Ils ne se connectent pas de façon interactive — leur `LastLogonDate` est trompeuse.

**Exemples :** `svc_backup`, `svc_monitoring`, `app_erp`

**Convention de nommage recommandée :** préfixe `svc_` ou `app_`  
**OU dédié recommandée :** `OU=Service_Accounts,DC=...`

**Conditions d'exemption :**
- Propriétaire applicatif documenté
- Droits minimum requis (pas de Domain Admin par défaut)
- Revue annuelle obligatoire

---

### Type 2 — BreakGlass
Comptes d'urgence permettant l'accès administrateur en cas de défaillance des systèmes d'authentification normaux.

**Règles strictes :**
- Maximum 2 comptes break-glass par organisation
- Exclus de **toutes** les politiques d'accès conditionnel
- Credentials en coffre physique — 2 personnes requises pour accès
- Alerte immédiate si connexion détectée
- Test trimestriel obligatoire (documenter les tests)
- Connexion non planifiée = incident de sécurité à traiter

---

### Type 3 — ExternalContractor
Consultants, prestataires ou experts externes avec des cycles de connexion irréguliers.

**Conditions d'exemption :**
- Contrat actif documenté avec date de fin
- Revue d'exemption = date de fin de contrat
- Connexion trimestrielle minimum attendue

**Attention :** à la fin du contrat, l'exemption expire automatiquement → traitement Leaver standard.

---

### Type 4 — LongLeave
Collaborateurs en absence longue durée (congé maternité/paternité, arrêt maladie, sabbatique).

**Conditions d'exemption :**
- Statut confirmé par la RH (document écrit)
- Date de retour prévisionnelle documentée
- Revue d'exemption = date de retour prévue
- À la date de retour : soit retrait de l'exemption, soit reconduction sur justification RH

**Important :** le compte reste désactivé si l'absence se prolonge au-delà de la date de retour sans renouvellement RH.

---

## Champs obligatoires dans exclusions.csv

| Champ | Description | Obligatoire |
|-------|-------------|-------------|
| `SamAccountName` | Login AD | ✅ |
| `DisplayName` | Nom affiché | ✅ |
| `ExclusionType` | ServiceAccount / BreakGlass / ExternalContractor / LongLeave | ✅ |
| `Reason` | Justification métier explicite | ✅ |
| `ExemptedBy` | EmployeeID du responsable ayant accordé l'exemption | ✅ |
| `ExemptionDate` | Date d'accordement de l'exemption | ✅ |
| `ReviewDate` | Date de prochaine revue — expiration automatique si dépassée | ✅ |
| `ExtensionAttribute` | Valeur AD pour le filtrage script (`Exempt_IGA` ou `Exempt_90J`) | Recommandé |

---

## Rapport d'exemptions — Livrable auditeur

À chaque exécution de `disable-inactive.ps1`, un rapport d'exclusions est généré :  
`output/exclusions_report_YYYYMMDD_HHmm.csv`

**Ce document répond à la question de l'auditeur :**  
*"Vous avez 47 comptes inactifs mais vous n'en avez désactivé que 38. Pourquoi ?"*  
→ Réponse : *"Les 9 restants sont dans la whitelist documentée — voici le rapport."*

---

## Revue des exemptions expirées

`disable-inactive.ps1` détecte automatiquement les exemptions dont la `ReviewDate` est dépassée  
et les traite comme des comptes standard (sans exemption).

**Fréquence recommandée :** revoir `exclusions.csv` lors de chaque campagne de recertification.

---

*Conformité : ISO 27001:2022 A.5.18 | NIST AC-2 — Exceptions documentées et révisées périodiquement*
