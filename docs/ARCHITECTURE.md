# Architecture technique - JuriBook

## Sommaire

- [Vue d'ensemble](#vue-densemble)
- [Diagramme des services](#diagramme-des-services)
- [Flux de communication](#flux-de-communication)
- [Décisions d'architecture (ADR)](#décisions-darchitecture-adr)
- [Sécurité](#sécurité)
- [Stratégie de persistance](#stratégie-de-persistance)
- [Infrastructure Kubernetes](#infrastructure-kubernetes)

---

## Vue d'ensemble

JuriBook suit une architecture **microservices événementielle** :

- Les appels **synchrones** (REST) passent exclusivement par l'`api-gateway` - aucun service n'est exposé directement.
- Les appels **asynchrones** (Kafka) permettent le découplage entre services (ex : une réservation créée publie un événement consommé par `notification-service` et `audit-service`).
- Chaque service possède sa **propre base de données PostgreSQL** (isolation complète, pas de jointures inter-services).

---

## Diagramme des services

```
                        ┌─────────────────────────────────────────────┐
                        │              FRONTEND (React 19)             │
                        │           http://localhost:5173              │
                        └───────────────────┬─────────────────────────┘
                                            │ HTTP/REST
                                            ▼
                        ┌─────────────────────────────────────────────┐
                        │           API GATEWAY (:8080)                │
                        │    Spring Cloud Gateway (WebMVC/Servlet)     │
                        │  • Validation JWT (sans appel auth-service)  │
                        │  • Routage par préfixe /api/**               │
                        │  • Routes publiques : /api/auth/**           │
                        │    /api/lawyers/search, /api/lawyers/{id}    │
                        └──┬──────────┬──────────┬──────────┬─────────┘
                           │          │          │          │
               ┌───────────▼─┐  ┌────▼──────┐  │    ┌─────▼──────────┐
               │ auth-service│  │lawyer-svc │  │    │booking-service │
               │   (:8081)   │  │  (:8082)  │  │    │    (:8083)     │
               │             │  │           │  │    │                │
               │ • Register  │  │ • Profils │  │    │ • Créneaux     │
               │ • Login     │  │ • Dispos  │  │    │ • Réservations │
               │ • Refresh   │  │ • Avis    │  │    │ • Annulations  │
               │ • Users     │  │ • Search  │  │    │                │
               └──────┬──────┘  └────┬──────┘  │    └───────┬────────┘
                      │              │          │            │
                   [DB auth]      [DB lawyer]   │        [DB booking]
                                               │
                              ┌────────────────┴───────────────────┐
                              │         KAFKA KRaft (:9092)         │
                              │                                     │
                              │  Topics :                           │
                              │  • booking-events                   │
                              │  • lawyer-events                    │
                              │  • audit-events                     │
                              └──────────┬──────────────┬──────────┘
                                         │              │
                              ┌──────────▼──┐  ┌────────▼───────┐
                              │notif-service│  │ audit-service  │
                              │  (:8084)    │  │   (:8085)      │
                              │             │  │                │
                              │ • In-app    │  │ • Journal      │
                              │ • Badge     │  │ • Abus (>5     │
                              │ • Mark read │  │   annulations  │
                              │             │  │   ou >3 avis   │
                              └─────────────┘  │   1★/24h)     │
                               [DB notifs]     └────────────────┘
                                                 [DB audit]
```

---

## Flux de communication

### Flux de réservation (exemple complet)

```
Client          API Gateway       booking-service      Kafka
  │                  │                  │                │
  │─── POST /api/bookings ──────────────▶│                │
  │                  │◀── JWT valid ─────│                │
  │                  │─── route ────────▶│                │
  │                  │                  │─ BookingCreated ▶│
  │                  │                  │                  │──▶ notification-service
  │                  │                  │                  │──▶ audit-service
  │◀── 201 Created ──────────────────────│                │
```

### Flux d'authentification

```
Client          API Gateway       auth-service
  │                  │                  │
  │─── POST /api/auth/login ────────────▶│  (route publique, bypass JWT)
  │                  │──────────────────▶│
  │                  │◀── {token, role} ─│
  │◀── 200 + JWT ────│                  │
  │                  │                  │
  │─── GET /api/bookings ───────────────▶│
  │   (Authorization: Bearer <jwt>)      │
  │                  │◀── JWT valide ?   │  (validation locale, clé symétrique)
  │                  │─── route ────────▶ booking-service
```

---

## Décisions d'architecture (ADR)

### ADR-001 — Spring Cloud Gateway en mode Servlet (WebMVC)

**Contexte** : Spring Cloud Gateway supporte deux modes : WebFlux (réactif) et WebMVC (Servlet, depuis Spring Boot 3.4+).

**Décision** : Mode WebMVC choisi.

**Raisons** : Cohérence avec les autres services (tous en Servlet/Spring MVC) ; évite de mixer deux modèles de threading dans l'équipe ; `SecurityConfig` CORS identique partout.

**Conséquence** : La validation JWT se fait dans un filtre `OncePerRequestFilter` classique, pas dans un `WebFilter` réactif.

---

### ADR-002 — Kafka KRaft (sans ZooKeeper)

**Contexte** : Kafka nécessitait historiquement ZooKeeper pour la coordination du cluster.

**Décision** : KRaft mode activé (`KAFKA_KRAFT_CLUSTER_ID` généré via `kafka-storage random-uuid`).

**Raisons** : Simplifie l'infrastructure (un seul processus) ; recommandé pour les nouveaux déploiements Kafka 3.x+.

**Contrainte Kubernetes** : `publishNotReadyAddresses: true` obligatoire sur le Service Kafka, sinon les brokers ne peuvent pas se joindre entre eux au démarrage.

---

### ADR-003 — Validation JWT locale dans la gateway

**Contexte** : Deux options pour valider les JWT : appel réseau vers `auth-service` à chaque requête, ou validation locale avec la clé symétrique.

**Décision** : Validation locale (clé symétrique partagée via `SECRET_KEY` en variable d'environnement).

**Raisons** : Élimine la dépendance réseau critique sur le chemin de chaque requête ; réduit la latence ; `auth-service` n'est pas un SPOF pour le routage.

**Conséquence** : La révocation de token n'est pas instantanée (le token reste valide jusqu'à expiration). Acceptable pour un access token de 24h.

---

### ADR-004 - CORS dans SecurityConfig uniquement

**Contexte** : Spring Security et Spring MVC ont chacun leur propre gestion CORS.

**Décision** : CORS configuré **uniquement** dans `SecurityConfig` via `.cors(cors -> cors.configurationSource(...))`. Aucun bean `CorsFilter` séparé.

**Raisons** : Deux sources CORS provoquent des headers dupliqués. Spring Security intercepte avant Spring MVC - sa config prime.

**Règle** : Ne jamais ajouter `@CrossOrigin` ou un bean `CorsFilter` dans aucun service.

---

### ADR-005 - Base de données par service (Database per Service)

**Contexte** : Pattern fondamental des microservices.

**Décision** : Chaque service a sa propre instance PostgreSQL sur Scaleway RDB.

**Conséquence** : Pas de jointures SQL inter-services. Les données dénormalisées nécessaires (ex : nom de l'avocat dans une notification) sont transmises via les événements Kafka ou récupérées par appel REST au service propriétaire.

---

### ADR-006 — Probes Kubernetes pour JVM lente au démarrage

**Contexte** : Les pods Spring Boot mettent 30–60s à démarrer, causant des `OOMKill` ou des restarts en boucle avec des `livenessProbe` trop agressives.

**Décision** : `startupProbe` avec `failureThreshold: 30` et `periodSeconds: 10` (= 5 minutes max) avant que `livenessProbe` ne prenne le relais.

**Pour Kafka spécifiquement** : Les probes utilisent `tcpSocket` (connexion TCP au port 9092), jamais `kafka-topics.sh --list` qui lance une JVM complète et consomme trop de ressources dans un probe.

---

## Sécurité

### Modèle d'authentification

```
┌──────────┐     Login      ┌─────────────┐
│  Client  │───────────────▶│ auth-service│
│          │◀───────────────│             │
│          │  access_token  │  JWT signé  │
│          │  (24h)         │  (HS256)    │
│          │  refresh_token │             │
│          │  (7j, rotatif) └─────────────┘
└──────────┘

Chaque requête API :
Authorization: Bearer <access_token>
         │
         ▼
   API Gateway
   (validation JWT locale)
         │
         ▼
   Service cible
```

### Rôles

| Rôle | Accès |
|------|-------|
| `CLIENT` | `/client/**`, `/search`, `/lawyers/**`, `/api/bookings` (ses RDV) |
| `LAWYER` | `/lawyer/**`, `/api/availabilities`, `/api/bookings` (ses RDV) |
| `ADMIN` | `/admin/**`, tous les endpoints admin |

### Routes publiques (bypass JWT)

- `POST /api/auth/login`
- `POST /api/auth/register`
- `POST /api/auth/register/lawyer`
- `POST /api/auth/refresh`
- `GET /api/lawyers/search`
- `GET /api/lawyers/{id}`

---

## Stratégie de persistance

### Migrations Flyway

Chaque service gère ses migrations dans `src/main/resources/db/migration/` :

```
V1__init_schema.sql
V2__add_index_email.sql
V3__add_column_suspended_reason.sql
...
```

Les migrations sont **irréversibles** et versionnées. Toute modification de schéma = nouvelle migration.

### Extensions PostgreSQL requises

Les bases staging/prod nécessitent les extensions suivantes (installées via job Kubernetes au premier déploiement) :

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "unaccent";
```

---

## Infrastructure Kubernetes

### Namespace et organisation

```
namespace: juribook
├── Deployments (1 par service)
├── Services (ClusterIP interne + NodePort gateway)
├── ConfigMaps (variables non-sensibles)
├── Secrets (JWT secret, DB passwords, Kafka credentials)
├── Ingress (ingress-nginx → api-gateway)
└── Jobs (rdb-extensions-job - one-shot PostgreSQL extensions)
```

### Ressources types par pod

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

> **Note** : `JAVA_OPTS: "-Xmx384m"` est obligatoire pour éviter les OOMKill. Sans cette limite, la JVM réserve par défaut 25% de la RAM du nœud, dépassant le limit du pod.

### Volumes Kafka

`fsGroup: 1000` doit être défini dans le `securityContext` du pod Kafka pour que le processus Kafka (UID 1000) ait les droits d'écriture sur le PersistentVolume monté.