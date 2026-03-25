# Cadre de Gouvernance IAM — Applicable à toute structure

> Ce document définit les principes, les processus et les délais  
> qui constituent la **Baseline de Gouvernance IAM** déployable dans toute organisation.  
>  
> Il est conçu pour être présenté en début de mission comme cadre de référence.

---

## Les 4 piliers universels

### Pilier 1 — Source de vérité
> *"Qui est qui ?"*

Aucun accès ne peut exister sans identité RH valide.  
La source RH (SIRH, fichier CSV authoritaire) est la **seule** référence.  
Tout compte sans correspondance RH est, par définition, un risque.

**Implémentation :** `employees.csv` + `audit-orphaned.ps1`

---

### Pilier 2 — Cycle de vie (JML)
> *"Que devient l'accès quand la personne change de situation ?"*

| Événement | Action | Délai maximal |
|-----------|--------|---------------|
| Arrivée (Joiner) | Provisionnement au groupe RBAC minimum | J+1 |
| Mutation (Mover) | Révocation ancien groupe AVANT nouveau | Jour même |
| Départ (Leaver) | Désactivation + révocation + quarantaine | < 24h |

**Implémentation :** `joiner.ps1` / `mover.ps1` / `leaver.ps1`

---

### Pilier 3 — Certification périodique
> *"Est-ce que les accès sont toujours légitimes ?"*

Les accès accordés hier peuvent être inadaptés aujourd'hui.  
La recertification force les managers à valider explicitement les droits de leur équipe.

| Fréquence | Périmètre | Responsable |
|-----------|-----------|-------------|
| Mensuelle | Comptes inactifs | IT / Sécurité |
| Trimestrielle | Tous les comptes actifs | Managers métier |
| Annuelle | Matrice RBAC complète | RSSI |
| À chaque départ | Comptes du collaborateur | RH + IT |

**Implémentation :** `generate-campaign.ps1` / `process-responses.ps1`

---

### Pilier 4 — Moindre privilège
> *"A-t-il juste ce qu'il faut pour travailler ?"*

Chaque utilisateur reçoit uniquement les droits nécessaires à son rôle.  
Aucun droit n'est accordé "par précaution" ou "pour simplifier".

**Règles concrètes :**
- Un utilisateur = un groupe métier minimum
- Un admin = deux comptes distincts (standard + admin)
- Un service account dans un groupe admin = justification documentée obligatoire

---

## Délais incompressibles — Tableau de référence

| Action | Délai | Justification |
|--------|-------|---------------|
| Désactivation Leaver | < 24h après départ confirmé | Risque d'accès non autorisé |
| Notification inactivité (J-7) | 7 jours avant désactivation | Délai manager pour réaction |
| Quarantaine avant suppression | 90 jours | RGPD + récupération possible ("test du cri") |
| Délai de grâce recertification | 15 jours | Temps manager pour répondre |
| Silence vaut accord | J+15 sans réponse | Règle contractuelle à documenter |
| Nettoyage comptes de service | 1 à 3 mois | Risque de casser tâche planifiée |
| Campagne recertification complète | 4 à 8 semaines calendaires | Inclut délais de réponse managers |

---

## Principe "Silence vaut accord"

> *Cette règle doit être formalisée dans la politique IAM de l'organisation avant application.*

**Définition :** Si un manager ne répond pas à une demande de validation d'accès dans le délai imparti (J+15), l'accès est considéré comme validé **sauf** si le compte est inactif depuis plus de 90 jours.

**Pourquoi cette distinction :**
- Un compte actif sans réponse = probablement utilisé, risque faible de le certifier automatiquement
- Un compte inactif +90j sans réponse = risque trop élevé pour une certification tacite → désactivation

**Clause recommandée dans la politique IAM :**
> *"Toute demande de recertification sans réponse dans un délai de 15 jours ouvrés sera traitée conformément au principe de certification tacite pour les comptes actifs, et de désactivation préventive pour les comptes inactifs depuis plus de 90 jours."*

---

## Adaptabilité par taille de structure

| Taille | Approche recommandée | Fréquence recertification |
|--------|---------------------|--------------------------|
| < 100 utilisateurs | Processus manuel + scripts ponctuels | Semestrielle |
| 100–500 utilisateurs | Scripts automatisés + revue manager | Trimestrielle |
| 500–2000 utilisateurs | Ce cadre complet | Trimestrielle |
| > 2000 utilisateurs | Outil IGA dédié (SailPoint, Saviynt...) | Continue |

---

*Arnaud MONTCHO — Consultant IAM/IGA — github.com/CrepuSkull*
