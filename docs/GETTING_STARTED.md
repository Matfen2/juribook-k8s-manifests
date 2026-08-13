# Guide de démarrage local - JuriBook

Ce guide permet à un développeur de relancer l'ensemble du projet en local à partir de zéro.

## Prérequis

| Outil | Version minimale | Vérification |
|-------|-----------------|-------------|
| Java | 21 | `java -version` |
| Maven | 3.9+ | `./mvnw -v` (wrapper inclus) |
| Docker Desktop | 24+ | `docker -v` |
| Docker Compose | v2 | `docker compose version` |
| Node.js | 20+ | `node -v` |
| npm | 10+ | `npm -v` |

---

## 1. Cloner les repos

```bash
# Créer un dossier racine
mkdir juribook && cd juribook

# Cloner tous les repos
git clone https://github.com/Matfen2/juribook-api-gateway
git clone https://github.com/Matfen2/juribook-auth-service
git clone https://github.com/Matfen2/juribook-lawyer-service
git clone https://github.com/Matfen2/juribook-booking-service
git clone https://github.com/Matfen2/juribook-notification-service
git clone https://github.com/Matfen2/juribook-audit-service
git clone https://github.com/Matfen2/juribook-frontend
git clone https://github.com/Matfen2/juribook-k8s-manifests
```

---

## 2. Démarrer l'infrastructure (Kafka + PostgreSQL)

Le `docker-compose.yml` se trouve à la racine de `juribook-k8s-manifests/` :

```bash
cd juribook-k8s-manifests
docker compose up -d
```

Ce Compose démarre :
- **Kafka KRaft** (port `9092`)
- **6 instances PostgreSQL** (ports `5432` à `5437`, une par service)

Vérifier que tout est up :

```bash
docker compose ps
```

Tous les conteneurs doivent afficher `running`.

### Variables d'environnement

Copier le fichier d'exemple et renseigner les valeurs :

```bash
cp .env.example .env
```

```env
# .env
JWT_SECRET=une_cle_secrete_d_au_moins_64_caracteres_pour_hs256_en_prod
KAFKA_BOOTSTRAP_SERVERS=localhost:9092

# Auth DB
AUTH_DB_URL=jdbc:postgresql://localhost:5432/auth_db
AUTH_DB_USER=auth_user
AUTH_DB_PASSWORD=auth_pass

# Lawyer DB
LAWYER_DB_URL=jdbc:postgresql://localhost:5433/lawyer_db
LAWYER_DB_USER=lawyer_user
LAWYER_DB_PASSWORD=lawyer_pass

# Booking DB
BOOKING_DB_URL=jdbc:postgresql://localhost:5434/booking_db
BOOKING_DB_USER=booking_user
BOOKING_DB_PASSWORD=booking_pass

# Notification DB
NOTIF_DB_URL=jdbc:postgresql://localhost:5435/notif_db
NOTIF_DB_USER=notif_user
NOTIF_DB_PASSWORD=notif_pass

# Audit DB
AUDIT_DB_URL=jdbc:postgresql://localhost:5436/audit_db
AUDIT_DB_USER=audit_user
AUDIT_DB_PASSWORD=audit_pass
```

> **Important** : `JWT_SECRET` doit être identique dans `api-gateway` et `auth-service`. Les deux services l'utilisent pour signer et valider les tokens.

---

## 3. Démarrer les services backend

Ouvrir un terminal par service (ou utiliser les profils Maven) :

```bash
# Terminal 1 - auth-service
cd juribook-auth-service
./mvnw spring-boot:run

# Terminal 2 - lawyer-service
cd juribook-lawyer-service
./mvnw spring-boot:run

# Terminal 3 - booking-service
cd juribook-booking-service
./mvnw spring-boot:run

# Terminal 4 - notification-service
cd juribook-notification-service
./mvnw spring-boot:run

# Terminal 5 - audit-service
cd juribook-audit-service
./mvnw spring-boot:run

# Terminal 6 - api-gateway (démarrer en dernier)
cd juribook-api-gateway
./mvnw spring-boot:run
```

### Ordre de démarrage recommandé

```
PostgreSQL & Kafka  →  auth-service  →  lawyer-service
                    →  booking-service
                    →  notification-service
                    →  audit-service
                    →  api-gateway   (en dernier)
```

> **Note** : Les services Spring Boot prennent 20-40s à démarrer (JVM + Flyway migrations). Attendre que chaque service affiche `Started Application in X seconds` avant de passer au suivant.

---

## 4. Démarrer le frontend

```bash
cd juribook-frontend
npm install
npm run dev
```

L'application est accessible sur **`http://localhost:5173`**.

### Variables d'environnement frontend

```bash
cp .env.example .env.local
```

```env
# .env.local
VITE_API_BASE_URL=http://localhost:8080
```

---

## 5. Vérifier que tout fonctionne

### Health checks

```bash
# API Gateway
curl http://localhost:8080/actuator/health

# Auth service (direct)
curl http://localhost:8081/actuator/health

# Via gateway — login test
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juribook.fr","password":"adminpass"}'
```

### Interface web

Ouvrir `http://localhost:5173` - la page de login JuriBook doit s'afficher.

---

## 6. Données de test (seed)

Pour peupler la base avec des données de démonstration :

```bash
cd juribook-auth-service
./mvnw spring-boot:run -Dspring-boot.run.profiles=seed
```

Comptes créés par le seed :

| Email | Mot de passe | Rôle |
|-------|-------------|------|
| `admin@juribook.fr` | `adminpass` | ADMIN |
| `jean.dupont@example.com` | `motdepasse123` | CLIENT |
| `sophie.martin@example.com` | `motdepasse123` | LAWYER |

---

## 7. Lancer les tests

### Tests unitaires (backend)

```bash
# Dans chaque dossier service
./mvnw test

# Tous les services en une commande (depuis la racine)
for service in auth lawyer booking notification audit api-gateway; do
  echo "=== Testing juribook-$service-service ==="
  cd juribook-${service}-service && ./mvnw test -q && cd ..
done
```

### Tests E2E Cypress (frontend)

```bash
cd juribook-frontend

# Mode interactif (navigateur Cypress ouvert)
npm run cypress:open

# Mode headless (CI / terminal)
npm run cypress:run
```

> Prérequis : tous les services backend doivent être démarrés avant de lancer Cypress.

**Résultats attendus : 43 tests au vert.**

---

## 8. Arrêter l'environnement

```bash
# Arrêter les services Spring Boot : Ctrl+C dans chaque terminal

# Arrêter l'infrastructure Docker
cd juribook-k8s-manifests
docker compose down

# Supprimer les volumes (reset complet des BDD)
docker compose down -v
```

---

## Problèmes fréquents

### Port déjà utilisé

```bash
# Trouver le processus sur le port 8080
lsof -i :8080
kill -9 <PID>
```

### Kafka ne démarre pas

Vérifier que le `KAFKA_KRAFT_CLUSTER_ID` est bien généré :

```bash
docker compose logs kafka | grep "Kafka Server started"
```

Si le volume Kafka est corrompu :

```bash
docker compose down -v
docker compose up -d
```

### Flyway - migration en erreur

```bash
# Repair Flyway (marque les migrations failed comme resolved)
./mvnw flyway:repair

# Puis relancer
./mvnw spring-boot:run
```

### `401 Unauthorized` sur toutes les requêtes

Vérifier que `JWT_SECRET` est bien **identique** dans `api-gateway` et `auth-service`. Une divergence de clé rend tous les tokens invalides.

### OOMKill sur les pods (si test avec Docker Compose multi-service)

Ajouter `JAVA_OPTS` dans le Compose :

```yaml
environment:
  JAVA_OPTS: "-Xmx384m -Xms128m"
```

---

## Structure d'un service backend (rappel)

```
juribook-[service]-service/
├── src/
│   ├── main/
│   │   ├── java/fr/juribook/[service]/
│   │   │   ├── config/          # SecurityConfig, KafkaConfig...
│   │   │   ├── controller/      # REST controllers
│   │   │   ├── service/         # Logique métier
│   │   │   ├── repository/      # JPA repositories
│   │   │   ├── entity/          # Entités JPA
│   │   │   ├── dto/             # Request/Response DTOs
│   │   │   └── kafka/           # Producers & Consumers
│   │   └── resources/
│   │       ├── application.yml
│   │       └── db/migration/    # Scripts Flyway (V1__, V2__...)
│   └── test/
├── Dockerfile                   # Multi-stage build
└── pom.xml                      # Maven indépendant (pas de parent POM)
```