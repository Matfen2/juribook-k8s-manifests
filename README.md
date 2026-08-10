# JuriBook - Manifestes Kubernetes

```
juribook-kubernetes/
├── 00-namespace.yaml
├── 01-secrets.yaml
├── 02-configmap.yaml
├── kafka.yaml                      ← StatefulSet Kafka KRaft + Service headless
├── kafka-init-job.yaml              ← Job one-shot : provisionne les 8 topics
├── mailhog.yaml
├── ingress.yaml
├── rdb-extensions-job.yaml           ← Job one-shot, déploiement cloud uniquement
├── postgres/                          ← Postgres local - usage Minikube uniquement
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

Manifestes Deployment/Service/Ingress pour les 6 microservices JuriBook, Kafka KRaft, PostgreSQL et MailHog. Applicables sur deux environnements distincts :
- **Local** (Minikube), 5 Postgres locaux, images buildées et chargées à la main
- **Cloud** (Scaleway Kapsule, dépôt `juribook-terraform`), base RDB managée, images poussées sur un registre, déploiement automatisé par CI/CD

**Statut : ✅ validé sur les deux environnements.** Testé de bout en bout en local (Minikube) et sur le cluster cloud Scaleway (`curl /actuator/health` → `{"status":"UP"}`).

---

## ⚠️ Leçons apprises - déjà corrigées ici, à ne pas redécouvrir

Quatre problèmes rencontrés en conditions réelles (Minikube puis Scaleway), tous déjà résolus dans les manifestes de ce dépôt.

### 1. Kafka en `CrashLoopBackOff` - DNS auto-référencé
Le broker KRaft doit se résoudre lui-même via `kafka-0.kafka` pour dialoguer avec le contrôleur. Un Service headless ne publie le DNS d'un pod qu'une fois ce pod `Ready` - boucle bloquante sans intervention.
**Fix** (déjà dans `kafka.yaml`) : `publishNotReadyAddresses: true` sur le Service.

### 2. Kafka - `path not writable` sur le volume
Certains CSI drivers cloud (ex: Scaleway) montent les PVC avec un propriétaire `root`, alors que `cp-kafka` tourne en UID/GID 1000.
**Fix** (déjà dans `kafka.yaml`) : `securityContext.fsGroup: 1000` au niveau du pod.

### 3. Kafka - erreur `lost+found` au démarrage
Les volumes formatés en ext4 (comportement courant chez les providers cloud) créent un dossier `lost+found` à leur racine ; Kafka refuse de démarrer si son répertoire de logs contient autre chose que des dossiers `topic-partition`.
**Fix** (déjà dans `kafka.yaml`) : `KAFKA_LOG_DIRS` pointe vers un sous-répertoire (`/var/lib/kafka/data/logs`), pas la racine du volume monté.

### 4. Microservices Java - `OOMKilled` et `CrashLoopBackOff` en boucle
Deux causes cumulées, corrigées dans les 6 fichiers `services/*.yaml` :
- **Mémoire** : `JAVA_OPTS=-XX:MaxRAMPercentage=75.0` injecté en variable d'environnement (le Dockerfile lit déjà `$JAVA_OPTS` dans son `ENTRYPOINT`).
- **CPU** : limite remontée à `1` vCPU (pas `500m`). Spring Boot est très gourmand en CPU au démarrage ; une limite trop stricte provoque un throttling si sévère que le pod n'a jamais le temps de finir de démarrer avant que la probe de liveness ne le tue, en boucle infinie.
- **`startupProbe`** ajoutée sur les 6 services (5 min de budget) : tant qu'elle n'a pas réussi une fois, `readiness`/`liveness` restent suspendues.

### 5. Registre privé Scaleway - `insufficient_scope` malgré `docker login` réussi (déploiement cloud)
Un `docker push` réussi depuis ta machine ne suffit pas : le **cluster Kapsule lui-même** a besoin de son propre secret Kubernetes pour tirer une image d'un registre privé. Copier `~/.docker/config.json` dans un secret ne fonctionne pas non plus si Docker Desktop délègue le stockage réel des credentials au gestionnaire Windows (`credsStore`), le fichier copié est alors vide de tokens exploitables.
**Fix** :
```powershell
kubectl create secret docker-registry regcred --docker-server=rg.fr-par.scw.cloud --docker-username=nologin --docker-password=<ta_secret_key> -n juribook
kubectl patch serviceaccount default -n juribook -p "{\"imagePullSecrets\": [{\"name\": \"regcred\"}]}"
```
Le ServiceAccount `default` du namespace hérite du secret pour tous les pods qui l'utilisent (cas de tous les nôtres).

---

## Déploiement local (Minikube)

### Prérequis
```powershell
docker build -t docker-auth-service:latest .
minikube image load docker-auth-service:latest
# répéter pour lawyer, booking, notification, audit, api-gateway

minikube addons enable ingress
```

### Ordre d'application
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

---

## Déploiement cloud (Scaleway Kapsule)

Les manifestes de `services/` sont déjà adaptés pour ce mode : `SPRING_DATASOURCE_URL` pointe vers l'IP privée RDB, les images pointent vers `rg.fr-par.scw.cloud/juribook/`.

### 1. Connecter kubectl au cluster
```powershell
scw k8s kubeconfig install <uuid_du_cluster> region=fr-par
kubectl get nodes
```

### 2. Créer le secret d'accès au registre privé
```powershell
kubectl create secret docker-registry regcred --docker-server=rg.fr-par.scw.cloud --docker-username=nologin --docker-password=<ta_secret_key> -n juribook
kubectl patch serviceaccount default -n juribook -p "{\"imagePullSecrets\": [{\"name\": \"regcred\"}]}"
```

### 3. Ne PAS appliquer le dossier `postgres/`
RDB (dépôt `juribook-terraform`) remplace les 5 conteneurs Postgres locaux.

### 4. Ordre d'application
```powershell
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secrets.yaml    # POSTGRES_PASSWORD doit matcher db_app_password de Terraform
kubectl apply -f 02-configmap.yaml

kubectl apply -f kafka.yaml
kubectl wait --for=condition=ready pod -l app=kafka -n juribook --timeout=120s
kubectl apply -f kafka-init-job.yaml
kubectl wait --for=condition=complete job/kafka-init -n juribook --timeout=60s

kubectl apply -f mailhog.yaml
kubectl apply -f services/
```

### 5. Créer les extensions SQL (une seule fois)
RDB n'a pas d'endpoint public, édite `rdb-extensions-job.yaml` (remplace `<db_admin_password>`), applique, vérifie, supprime :
```powershell
kubectl apply -f rdb-extensions-job.yaml
kubectl wait --for=condition=complete job/rdb-extensions-init -n juribook --timeout=60s
kubectl logs job/rdb-extensions-init -n juribook
kubectl delete -f rdb-extensions-job.yaml
```

### 6. Ingress Controller (absent par défaut sur Kapsule)
```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl apply -f ingress.yaml
```

---

## Vérifier le déploiement (les deux environnements)
```powershell
kubectl get pods -n juribook
kubectl top pods -n juribook

kubectl port-forward svc/api-gateway 8080:8080 -n juribook
curl http://localhost:8080/actuator/health
```

---

## Intégration CI/CD

Chaque dépôt de microservice (`juribook-auth-service`, etc.) possède son propre pipeline GitHub Actions qui, à chaque merge sur `develop`, build/teste/pousse une nouvelle image et exécute :
```bash
kubectl set image deployment/<service> <service>=rg.fr-par.scw.cloud/juribook/<service>:<sha> -n juribook
```

**⚠️ Limite connue** : cette commande modifie le Deployment directement dans le cluster, sans mettre à jour les fichiers YAML de ce dépôt (qui référencent encore `:latest`). Si tu relances `kubectl apply -f services/` après un déploiement CI, ça écrase la version déployée par la CI et revient à l'ancienne image. Pistes pour résoudre ça plus tard : GitOps (Flux/ArgoCD) ou auto-commit du tag depuis la CI, non implémenté à ce stade, acceptable pour un projet portfolio.

## Monitoring

### Health checks applicatifs

Chaque microservice expose `/actuator/health` via Spring Boot Actuator. Les probes Kubernetes s'en servent directement :

| Service | Port | Endpoint |
|---|---|---|
| api-gateway | 8080 | `http://api-gateway:8080/actuator/health` |
| auth-service | 8081 | `http://auth-service:8081/actuator/health` |
| lawyer-service | 8082 | `http://lawyer-service:8082/actuator/health` |
| booking-service | 8083 | `http://booking-service:8083/actuator/health` |
| notification-service | 8084 | `http://notification-service:8084/actuator/health` |
| audit-service | 8085 | `http://audit-service:8085/actuator/health` |

Vérification manuelle depuis l'extérieur du cluster (via le Load Balancer) :
```powershell
curl -H "Host: juribook.local" http://<INGRESS_LB_IP>/actuator/health
# Réponse attendue : {"status":"UP"}
```

Vérification de tous les pods en une commande :
```powershell
kubectl get pods -n juribook
# Tous les services doivent être 1/1 Running
```

### Observabilité cloud — Scaleway Cockpit

L'infrastructure est connectée à **Scaleway Cockpit** (Grafana managé). Accessible via : Console Scaleway → Monitoring → Cockpit → Access Grafana.

Deux datasources disponibles nativement :

| Datasource | Type | Contenu |
|---|---|---|
| Scaleway Logs - fr-par | Loki | Logs infrastructure : autoscaler Kapsule, RDB PostgreSQL, CSI plugin |
| Scaleway Metrics - fr-par | Prometheus | Métriques cluster : CPU/RAM nodes, réseau, volumes |

**Logs applicatifs des pods** : non collectés nativement par Scaleway Cockpit (nécessiterait un DaemonSet Grafana Alloy ou un Control Plane dédié). En attendant, les logs sont accessibles via CLI :
```powershell
# Logs d'un service spécifique
kubectl logs -n juribook -l app=auth-service --tail=100

# Logs en temps réel
kubectl logs -n juribook -l app=api-gateway -f

# Logs de tous les services en une passe
foreach ($svc in @("auth-service","lawyer-service","booking-service","notification-service","audit-service","api-gateway")) {
    Write-Host "=== $svc ===" -ForegroundColor Cyan
    kubectl logs -n juribook -l app=$svc --tail=20
}
```

### Métriques cluster en temps réel
```powershell
# Consommation CPU/RAM par pod
kubectl top pods -n juribook

# Consommation par node
kubectl top nodes
```

---

## Nettoyage
```powershell
kubectl delete namespace juribook
```

## Dépôts liés

| Dépôt | Rôle |
|---|---|
| `juribook-docker` | Environnement local (Docker Compose) |
| `juribook-kubernetes` | Ce dépôt : manifestes K8s |
| `juribook-terraform` | Infrastructure cloud (Kapsule, RDB, DNS) |
| `juribook-auth-service` et 5 autres | Code applicatif + pipeline CI/CD |