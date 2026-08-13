# JuriBook - Le Doctolib des avocats

> Plateforme de mise en relation entre clients et avocats : recherche par spécialité et ville, réservation en ligne, gestion des disponibilités, notifications in-app, modération des avis.

![Stack](https://img.shields.io/badge/Java_21-Spring_Boot_4.1-blue) ![Stack](https://img.shields.io/badge/React_19-TypeScript-61DAFB) ![Stack](https://img.shields.io/badge/Kafka_KRaft-PostgreSQL_16-orange) ![Stack](https://img.shields.io/badge/Kubernetes-Scaleway_Kapsule-green)

---

## Sommaire

- [Vue d'ensemble](#vue-densemble)
- [Stack technique](#stack-technique)
- [Structure des repos](#structure-des-repos)
- [Démarrage rapide](#démarrage-rapide)
- [Architecture microservices](#architecture-microservices)
- [Tests](#tests)
- [CI/CD](#cicd)
- [Infrastructure](#infrastructure)
- [Auteur](#auteur)

---

## Vue d'ensemble

JuriBook est une application full-stack composée de **6 microservices Spring Boot** et d'un **frontend React**, communiquant via Kafka (événements asynchrones) et REST (requêtes synchrones). Un `api-gateway` centralise l'authentification JWT et le routage.

### Fonctionnalités principales

| Rôle | Fonctionnalités |
|------|----------------|
| **Client** | Inscription, recherche d'avocats, réservation, historique RDV, avis, notifications |
| **Avocat** | Gestion des disponibilités, confirmation/annulation de RDV, profil |
| **Admin** | Validation des profils avocats, analytics, journal d'audit, modération des avis, alertes d'abus |

---

## Stack technique

| Couche | Technologie |
|--------|------------|
| Backend | Java 21 / Spring Boot 4.1.0 / Spring Security / Spring Cloud Gateway |
| Base de données | PostgreSQL 16 (une DB par service) / Flyway (migrations) |
| Messaging | Apache Kafka KRaft (sans ZooKeeper) |
| Frontend | React 19 / TypeScript / Vite / Tailwind CSS v4 / Framer Motion |
| Auth | JWT (access 24h + refresh 7j rotatif) / HttpOnly cookies |
| Conteneurs | Docker (multi-stage builds) / Docker Compose (local) |
| Orchestration | Kubernetes / Scaleway Kapsule |
| IaC | Terraform (Scaleway provider) |
| CI/CD | GitHub Actions (build → push GHCR → deploy Kapsule) |
| Monitoring | Scaleway Cockpit / Grafana Alloy |
| Tests E2E | Cypress 13 (43 tests) |

---

## Structure des repos

```
Matfen2/
├── juribook-auth-service        # Authentification & gestion des utilisateurs
├── juribook-lawyer-service      # Profils avocats, disponibilités, avis
├── juribook-booking-service     # Réservations & créneaux
├── juribook-notification-service # Notifications in-app
├── juribook-audit-service       # Journal d'audit & détection d'abus
├── juribook-api-gateway         # Spring Cloud Gateway + validation JWT
├── juribook-frontend            # React 19 + TypeScript
└── juribook-k8s-manifests       # Manifestes Kubernetes & Terraform
```

Chaque service backend est un projet Maven **indépendant** (pas de parent POM).

---

## Démarrage rapide

Voir le [Guide de démarrage local](./docs/GETTING_STARTED.md) pour les instructions complètes Docker Compose.

```bash
# Cloner tous les repos
git clone https://github.com/Matfen2/juribook-api-gateway
git clone https://github.com/Matfen2/juribook-auth-service
git clone https://github.com/Matfen2/juribook-lawyer-service
git clone https://github.com/Matfen2/juribook-booking-service
git clone https://github.com/Matfen2/juribook-notification-service
git clone https://github.com/Matfen2/juribook-audit-service
git clone https://github.com/Matfen2/juribook-frontend

# Démarrer l'infrastructure (Kafka + PostgreSQL)
cd juribook-k8s-manifests
docker compose up -d

# Démarrer chaque service (dans des terminaux séparés)
cd juribook-auth-service && ./mvnw spring-boot:run
# ... (répéter pour chaque service)

# Démarrer le frontend
cd juribook-frontend && npm install && npm run dev
```

L'application est accessible sur `http://localhost:5173`.

---

## Architecture microservices

Voir le [document d'architecture](./docs/ARCHITECTURE.md) pour le diagramme complet et les décisions de conception (ADR).

**Ports locaux par défaut :**

| Service | Port |
|---------|------|
| api-gateway | 8080 |
| auth-service | 8081 |
| lawyer-service | 8082 |
| booking-service | 8083 |
| notification-service | 8084 |
| audit-service | 8085 |
| frontend (Vite) | 5173 |
| Kafka | 9092 |
| PostgreSQL | 5432–5437 |

---

## Tests

```bash
# Tests unitaires (chaque service)
./mvnw test

# Tests E2E Cypress (frontend)
cd juribook-frontend
npm run cypress:open   # mode interactif
npm run cypress:run    # mode headless (CI)
```

**Couverture Cypress : 43 tests au vert** répartis sur :
- `auth-flow.cy.ts` - inscription, connexion, déconnexion, routes protégées
- `notifications-flow.cy.ts` - badge, liste, mark-as-read
- *(autres suites par feature)*

---

## CI/CD

Chaque push sur `main` déclenche le pipeline GitHub Actions :

1. **Build** - `mvn package` / `npm run build`
2. **Docker** - build multi-stage + push sur GHCR
3. **Approval** - gate manuel avant déploiement en production
4. **Deploy** - `kubectl rollout` sur Scaleway Kapsule

---

## Infrastructure

L'infrastructure Scaleway est provisionnée via Terraform (repo `juribook-k8s-manifests/terraform/`) :

- **Kapsule** - cluster Kubernetes managé
- **RDB** - PostgreSQL 16 managé (une instance par service, réseau privé)
- **Cockpit** - métriques & logs via Grafana Alloy

---

## Auteur

**Mathieu Fenouil** — Développeur Full-Stack (Java / Spring Boot + React / TypeScript)

- GitHub : [github.com/Matfen2](https://github.com/Matfen2)
- LinkedIn : [linkedin.com/in/mathieu-fenouil-développeur-full-stack](https://www.linkedin.com/in/mathieu-fenouil-développeur-full-stack/)