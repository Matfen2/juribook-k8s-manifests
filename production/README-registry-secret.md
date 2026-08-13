# Secret d'accès au registre - PRODUCTION

Comme pour le staging, le namespace `juribook-production` a besoin de son propre secret pour tirer les images privées depuis `rg.fr-par.scw.cloud` :

```powershell
kubectl create secret docker-registry regcred --docker-server=rg.fr-par.scw.cloud --docker-username=nologin --docker-password=<ta_secret_key> -n juribook-production
kubectl patch serviceaccount default -n juribook-production -p "{\"imagePullSecrets\": [{\"name\": \"regcred\"}]}"
```
