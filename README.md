# JuriBook — Manifestes Kubernetes

Sprint 8.2 — reconstruit intégralement après une première phase de test réel sur Minikube et Scaleway Kapsule, avec chaque problème rencontré déjà corrigé dans les manifestes ci-dessous. Reproduit l'architecture du `docker-compose.yml` local : Kafka KRaft, 5 bases PostgreSQL, 6 microservices, MailHog, exposés via un Ingress unique sur `api-gateway`.

## Structure

```
k8s/
├── 00-namespace.yaml
├── 01-secrets.yaml
├── 02-configmap.yaml
├── kafka.yaml                      # StatefulSet Kafka KRaft + Service headless
├── kafka-init-job.yaml             # Job one-shot : provisionne les 8 topics
├── mailhog.yaml
├── ingress.yaml
├── postgres/                       # Postgres local — usage Minikube uniquement
│   ├── 00-init-scripts-configmaps.yaml
│   └── postgres-{auth,lawyer,booking,notification,audit}.yaml
└── services/
    ├── auth-service.yaml
    ├── lawyer-service.yaml
    ├── booking-service.yaml
    ├── notification-service.yaml
    ├── audit-service.yaml
    └── api-gateway.yaml
```

---

## ⚠️ Leçons apprises — déjà corrigées ici, à ne pas redécouvrir

Ces quatre problèmes sont survenus lors des tests réels (Minikube puis Scaleway Kapsule) et sont déjà résolus dans les fichiers de ce dépôt. Les documenter évite de perdre du temps à les redébugger si les manifestes sont copiés ou adaptés ailleurs.

### 1. Kafka en `CrashLoopBackOff` — DNS auto-référencé
Le broker KRaft doit se résoudre lui-même via `kafka-0.kafka` pour dialoguer avec le contrôleur. Un Service headless ne publie le DNS d'un pod qu'une fois ce pod `Ready` — boucle bloquante sans intervention.
**Fix** (déjà dans `kafka.yaml`) : `publishNotReadyAddresses: true` sur le Service.

### 2. Kafka — `path not writable` sur le volume
Certains CSI drivers cloud (ex: Scaleway) montent les PVC avec un propriétaire `root`, alors que `cp-kafka` tourne en UID/GID 1000.
**Fix** (déjà dans `kafka.yaml`) : `securityContext.fsGroup: 1000` au niveau du pod.

### 3. Kafka — erreur `lost+found` au démarrage
Les volumes formatés en ext4 créent un dossier `lost+found` à leur racine ; Kafka refuse de démarrer si son répertoire de logs contient autre chose que des dossiers `topic-partition`.
**Fix** (déjà dans `kafka.yaml`) : `KAFKA_LOG_DIRS` pointe vers un sous-répertoire (`/var/lib/kafka/data/logs`), pas la racine du volume monté.

### 4. Microservices Java — `OOMKilled` et `CrashLoopBackOff` en boucle
Deux causes cumulées, corrigées dans les 6 fichiers `services/*.yaml` :
- **Mémoire** : `JAVA_OPTS=-XX:MaxRAMPercentage=75.0` injecté en variable d'environnement (le Dockerfile lit déjà `$JAVA_OPTS` dans son `ENTRYPOINT`) — sans ça, la JVM peut mal évaluer la mémoire réellement disponible dans le conteneur.
- **CPU** : limite remontée à `1` vCPU (pas `500m`). Spring Boot est très gourmand en CPU au démarrage (JIT, chargement de classes) ; une limite trop stricte provoque un throttling si sévère que le pod n'a jamais le temps de finir de démarrer avant que la probe de liveness ne le tue, en boucle infinie.
- **`startupProbe`** ajoutée sur les 6 services (`failureThreshold: 30` × `periodSeconds: 10` = 5 min de budget) : tant qu'elle n'a pas réussi une fois, `readiness`/`liveness` restent suspendues, évitant de tuer un pod encore en train de démarrer sous charge partagée.

---

## Prérequis

### Images

Sur Minikube/Kind, il faut build puis charger chaque image manuellement (K8s ne build pas comme Docker Compose) :
```powershell
docker build -t docker-auth-service:latest .
minikube image load docker-auth-service:latest
# répéter pour lawyer, booking, notification, audit, api-gateway
```

### Ingress Controller
```powershell
minikube addons enable ingress
```

---

## Ordre d'application (local — Minikube)

```powershell
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secrets.yaml
kubectl apply -f 02-configmap.yaml

kubectl apply -f postgres/00-init-scripts-configmaps.yaml
kubectl apply -f postgres/
kubectl apply -f kafka.yaml

kubectl wait --for=condition=ready pod -l app=kafka -n juribook --timeout=120s
kubectl apply -f kafka-init-job.yaml
kubectl wait --for=condition=complete job/kafka-init -n juribook --timeout=60s

kubectl apply -f mailhog.yaml
kubectl apply -f services/
kubectl apply -f ingress.yaml
```

## Vérifier le déploiement

```powershell
kubectl get pods -n juribook
kubectl top pods -n juribook    # vérifie qu'aucun pod n'approche ses limites CPU/mémoire

kubectl port-forward svc/api-gateway 8080:8080 -n juribook
curl http://localhost:8080/actuator/health
```

---

## ☁️ Adapter pour un déploiement cloud

Pour déployer sur un cluster managé (Scaleway Kapsule, EKS, etc.) avec une base de données managée externe plutôt que les 5 Postgres locaux :

1. **Ne pas appliquer le dossier `postgres/`** — la base managée le remplace.
2. **Dans chaque `services/*.yaml`**, remplacer `SPRING_DATASOURCE_URL` (actuellement `jdbc:postgresql://postgres-<service>:5432/<db>`) par l'endpoint de ta base managée, en ajoutant `?sslmode=require` si elle l'exige.
3. **Remplacer `image: docker-<service>:latest`** par l'URL de ton registre cloud (ex: `rg.fr-par.scw.cloud/<namespace>/<service>:latest`), et passer `imagePullPolicy` à `Always`.
4. **Adapter les `initContainers` `wait-for-postgres-*`** pour pointer vers l'IP/le host de la base managée plutôt que vers les Services Postgres locaux (qui n'existeront plus).
5. **Vérifier le dimensionnement du nœud/node pool** : Kafka + MailHog + 6 microservices Java tournant simultanément ont besoin d'au moins ~4-8 Go de RAM et plusieurs vCPU de marge pour absorber les pics de démarrage — un nœud d'entrée de gamme (2-4 Go) peut se révéler insuffisant, comme observé en pratique.
6. **Créer les extensions SQL manuellement** si ta base managée ne le permet pas via script d'init automatique (`uuid-ossp`, `pgcrypto`, `unaccent`) — généralement via un Job Kubernetes ponctuel exécuté une fois depuis l'intérieur du cluster si la base n'a pas d'endpoint public.

## Nettoyage

```powershell
kubectl delete namespace juribook
```
