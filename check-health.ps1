# ===============================================================
# check-health.ps1 - Vue d'ensemble de la sante des 12
# microservices (6 staging + 6 production) en une commande.
#
# Utilise "kubectl exec" pour lancer curl depuis l'interieur
# d'un pod deja en cours d'execution dans chaque namespace,
# plutot que d'ouvrir un port-forward par service un par un.
#
# Usage :
#   .\check-health.ps1
# ===============================================================

$services = @(
    "auth-service",
    "lawyer-service",
    "booking-service",
    "notification-service",
    "audit-service",
    "api-gateway"
)

$ports = @{
    "auth-service"         = 8081
    "lawyer-service"       = 8082
    "booking-service"      = 8083
    "notification-service" = 8084
    "audit-service"        = 8085
    "api-gateway"          = 8080
}

$namespaces = @("juribook", "juribook-production")

Write-Host ""
Write-Host "=== JuriBook - Vue d'ensemble sante des microservices ===" -ForegroundColor Cyan
Write-Host ""

$results = @()

foreach ($ns in $namespaces) {
    foreach ($svc in $services) {
        $port = $ports[$svc]

        $podName = kubectl get pods -n $ns -l "app=$svc" --field-selector=status.phase=Running -o jsonpath="{.items[0].metadata.name}" 2>$null

        if (-not $podName) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                Service   = $svc
                Status    = "NO POD RUNNING"
                Detail    = "-"
            }
            continue
        }

        $healthJson = kubectl exec -n $ns $podName -- curl -s "http://localhost:$port/actuator/health" 2>$null

        if ($healthJson -match '"status"\s*:\s*"UP"') {
            $status = "UP"
        } elseif ($healthJson) {
            $status = "DOWN"
        } else {
            $status = "UNREACHABLE"
        }

        $results += [PSCustomObject]@{
            Namespace = $ns
            Service   = $svc
            Status    = $status
            Detail    = $healthJson
        }
    }
}

$results | Format-Table Namespace, Service, Status -AutoSize

$downCount = ($results | Where-Object { $_.Status -ne "UP" }).Count
if ($downCount -eq 0) {
    Write-Host ""
    Write-Host "Tous les services sont UP (12/12)." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "$downCount service(s) ne repondent pas correctement :" -ForegroundColor Red
    $results | Where-Object { $_.Status -ne "UP" } | ForEach-Object {
        Write-Host "  - [$($_.Namespace)] $($_.Service): $($_.Status)" -ForegroundColor Yellow
    }
}
