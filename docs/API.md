# Documentation API - JuriBook

Tous les endpoints sont exposés via l'`api-gateway` sur le port `8080` (local) ou via l'Ingress en production. Le préfixe `/api` est ajouté par la gateway, les services internes écoutent sans ce préfixe.

## Sommaire

- [Authentification](#authentification--auth-service)
- [Avocats](#avocats--lawyer-service)
- [Réservations](#réservations--booking-service)
- [Notifications](#notifications--notification-service)
- [Audit](#audit--audit-service)
- [Admin — Utilisateurs](#admin--utilisateurs-auth-service)
- [Admin — Avis](#admin--modération-des-avis-lawyer-service)
- [Codes d'erreur communs](#codes-derreur-communs)

---

## Authentification - auth-service

Base URL : `/api/auth`

> Ces routes sont **publiques** (pas de JWT requis).

### `POST /api/auth/register`

Inscription d'un client.

**Body**
```json
{
  "name": "Jean Dupont",
  "email": "jean@example.com",
  "password": "motdepasse123",
  "phone": "0612345678"
}
```

**Réponses**

| Code | Description |
|------|-------------|
| `201` | Compte créé. Retourne `{ id, name, email, role, message }` |
| `409` | Email déjà utilisé - `{ message: "Email déjà utilisé" }` |
| `400` | Données invalides |

---

### `POST /api/auth/register/lawyer`

Inscription d'un avocat (profil soumis à validation admin).

**Body**
```json
{
  "name": "Maître Sophie Martin",
  "email": "sophie@barreau.fr",
  "password": "motdepasse123",
  "phone": "0612345678",
  "barNumber": "75001",
  "specialty": "Droit du travail",
  "city": "Paris"
}
```

**Réponses**

| Code | Description |
|------|-------------|
| `201` | Dossier soumis, en attente de validation |
| `409` | Email ou numéro de barreau déjà utilisé |

---

### `POST /api/auth/login`

Connexion - retourne les tokens JWT.

**Body**
```json
{
  "email": "jean@example.com",
  "password": "motdepasse123"
}
```

**Réponse `200`**
```json
{
  "id": 1,
  "name": "Jean Dupont",
  "email": "jean@example.com",
  "role": "CLIENT",
  "token": "<access_jwt>",
  "refreshToken": "<refresh_jwt>",
  "type": "Bearer"
}
```

| Code | Description |
|------|-------------|
| `200` | Connexion réussie |
| `401` | Email ou mot de passe incorrect |
| `403` | Compte suspendu |

---

### `POST /api/auth/refresh`

Renouvellement du token d'accès via le refresh token.

**Body**
```json
{ "refreshToken": "<refresh_jwt>" }
```

**Réponse `200`**
```json
{ "token": "<nouveau_access_jwt>" }
```

| Code | Description |
|------|-------------|
| `200` | Nouveau token généré |
| `401` | Refresh token expiré ou invalide |

---

## Avocats - lawyer-service

Base URL : `/api/lawyers`

### `GET /api/lawyers/search` *(public)*

Recherche d'avocats par spécialité et/ou ville.

**Query params**

| Param | Type | Description |
|-------|------|-------------|
| `specialty` | string | Filtrer par spécialité (ex: "Droit du travail") |
| `city` | string | Filtrer par ville (recherche insensible aux accents) |
| `page` | int | Page (défaut : 0) |
| `size` | int | Taille de page (défaut : 10) |

**Réponse `200`**
```json
{
  "content": [
    {
      "id": 2,
      "name": "Maître Sophie Martin",
      "specialty": "Droit du travail",
      "city": "Paris",
      "rating": 4.7,
      "reviewCount": 23
    }
  ],
  "totalElements": 1,
  "totalPages": 1,
  "number": 0
}
```

---

### `GET /api/lawyers/{id}` *(public)*

Détail d'un profil avocat.

**Réponse `200`**
```json
{
  "id": 2,
  "name": "Maître Sophie Martin",
  "email": "sophie@barreau.fr",
  "specialty": "Droit du travail",
  "barNumber": "75001",
  "address": { "city": "Paris" },
  "rating": 4.7,
  "reviewCount": 23,
  "enabled": true
}
```

| Code | Description |
|------|-------------|
| `200` | Profil trouvé |
| `404` | Avocat introuvable |

---

### `GET /api/lawyers/{id}/availabilities` 🔒

Créneaux disponibles d'un avocat.

**Headers** : `Authorization: Bearer <token>`

**Query params**

| Param | Type | Description |
|-------|------|-------------|
| `from` | date | Date de début (ISO 8601, ex: `2026-08-01`) |
| `to` | date | Date de fin |

**Réponse `200`**
```json
[
  {
    "id": 10,
    "date": "2026-08-15",
    "startTime": "09:00",
    "endTime": "09:30",
    "available": true
  }
]
```

---

### `POST /api/lawyers/availabilities` 🔒 *(LAWYER)*

Création d'une plage de disponibilité.

**Body**
```json
{
  "date": "2026-08-15",
  "startTime": "09:00",
  "endTime": "17:00",
  "slotDurationMinutes": 30
}
```

**Réponse `201`** : liste des créneaux générés.

---

### `GET /api/lawyers/{id}/reviews` 🔒

Avis vérifiés d'un avocat (uniquement après consultation terminée).

**Réponse `200`**
```json
[
  {
    "id": 5,
    "rating": 5,
    "comment": "Très professionnel",
    "clientId": 1,
    "bookingId": 42,
    "visible": true,
    "createdAt": "2026-08-10T10:00:00"
  }
]
```

---

### `POST /api/lawyers/{id}/reviews` 🔒 *(CLIENT)*

Déposer un avis après une consultation terminée.

**Body**
```json
{
  "bookingId": 42,
  "rating": 5,
  "comment": "Très professionnel"
}
```

| Code | Description |
|------|-------------|
| `201` | Avis créé |
| `400` | Réservation non éligible (pas terminée ou avis déjà déposé) |
| `409` | Avis déjà déposé pour cette réservation |

---

## Réservations - booking-service

Base URL : `/api/bookings`

### `GET /api/bookings` 🔒

Historique des réservations de l'utilisateur connecté.

**Réponse `200`**
```json
[
  {
    "id": 42,
    "lawyerId": 2,
    "slotId": 10,
    "date": "2026-08-15",
    "startTime": "09:00",
    "endTime": "09:30",
    "status": "CONFIRMED",
    "reason": "Litige locatif"
  }
]
```

Statuts possibles : `PENDING` | `CONFIRMED` | `COMPLETED` | `CANCELLED`

---

### `POST /api/bookings` 🔒 *(CLIENT)*

Créer une réservation.

**Body**
```json
{
  "slotId": 10,
  "reason": "Litige locatif"
}
```

**Réponse `201`**
```json
{
  "id": 42,
  "lawyerId": 2,
  "slotId": 10,
  "status": "PENDING"
}
```

| Code | Description |
|------|-------------|
| `201` | Réservation créée |
| `409` | Créneau déjà réservé |
| `400` | Créneau invalide ou client suspendu |

---

### `PATCH /api/bookings/{id}/confirm` 🔒 *(LAWYER)*

Confirmer une réservation.

**Réponse `200`** : réservation avec `status: "CONFIRMED"`.

---

### `PATCH /api/bookings/{id}/cancel` 🔒

Annuler une réservation (client ou avocat).

**Body** *(optionnel)*
```json
{ "reason": "Indisponibilité" }
```

> Au-delà de 5 annulations en 7 jours, le compte est automatiquement suspendu par `audit-service`.

---

### `POST /api/bookings/{id}/documents` 🔒 *(CLIENT)*

Uploader un document lié à une réservation.

**Body** : `multipart/form-data` avec le fichier.

**Réponse `201`** : métadonnées du document uploadé.

---

## Notifications - notification-service

Base URL : `/api/notifications`

### `GET /api/notifications/unread-count` 🔒

Nombre de notifications non lues (utilisé pour le badge).

**Réponse `200`**
```json
{ "count": 3 }
```

---

### `GET /api/notifications` 🔒

Liste complète des notifications de l'utilisateur.

**Réponse `200`**
```json
[
  {
    "id": 1,
    "type": "BOOKING_CONFIRMED",
    "message": "Votre rendez-vous avec Sophie Martin est confirmé pour le 15 août 2026 à 09:00",
    "bookingId": 42,
    "read": false,
    "createdAt": "2026-08-13T10:00:00"
  }
]
```

Types de notification : `BOOKING_CREATED` | `BOOKING_CONFIRMED` | `BOOKING_REMINDER` | `SLOT_RELEASED`

---

### `PATCH /api/notifications/{id}/read` 🔒

Marquer une notification comme lue.

**Réponse `200`** : `{}`

---

## Audit - audit-service

Base URL : `/api/audit`

> Tous les endpoints audit sont réservés au rôle `ADMIN`.

### `GET /api/audit` 🔒 *(ADMIN)*

Journal d'audit paginé.

**Query params** : `page`, `size`, `userId`, `action`, `from`, `to`

**Réponse `200`**
```json
{
  "content": [
    {
      "id": 1,
      "userId": 1,
      "action": "BOOKING_CANCELLED",
      "details": "Réservation #42 annulée",
      "createdAt": "2026-08-13T10:00:00"
    }
  ],
  "totalElements": 150,
  "totalPages": 15
}
```

---

## Admin - Utilisateurs (auth-service)

Base URL : `/api/admin/users`

> Tous les endpoints sont réservés au rôle `ADMIN`.

### `GET /api/admin/users` 🔒 *(ADMIN)*

Liste paginée des utilisateurs avec filtres.

**Query params**

| Param | Type | Description |
|-------|------|-------------|
| `role` | string | `CLIENT`, `LAWYER`, `ADMIN` |
| `enabled` | boolean | Comptes actifs ou suspendus |
| `suspensionSource` | string | `ABUSE_DETECTION`, `MANUAL` |
| `page` | int | Page |
| `size` | int | Taille |

---

### `PATCH /api/admin/users/{id}/activate` 🔒 *(ADMIN)*

Réactiver un compte suspendu.

**Réponse `200`** : utilisateur avec `enabled: true`.

---

### `PATCH /api/admin/users/{id}/suspend` 🔒 *(ADMIN)*

Suspendre manuellement un compte.

**Body**
```json
{ "reason": "Comportement abusif signalé" }
```

---

### `PATCH /api/admin/lawyers/{id}/validate` 🔒 *(ADMIN)*

Valider le profil d'un avocat (activation après vérification du dossier).

**Réponse `200`** : profil avec `enabled: true`.

---

## Admin - Modération des avis (lawyer-service)

Base URL : `/api/admin/reviews`

### `GET /api/admin/reviews` 🔒 *(ADMIN)*

Liste des avis pour modération, triés par note croissante.

**Query params** : `visible` (boolean), `page`, `size`

---

### `PATCH /api/admin/reviews/{id}/hide` 🔒 *(ADMIN)*

Masquer un avis (visible = false, non supprimé).

---

### `PATCH /api/admin/reviews/{id}/unhide` 🔒 *(ADMIN)*

Remettre un avis en ligne.

---

### `DELETE /api/admin/reviews/{id}` 🔒 *(ADMIN)*

Supprimer définitivement un avis.

---

## Codes d'erreur communs

| Code | Signification |
|------|--------------|
| `400` | Données invalides (validation Bean) |
| `401` | Token manquant, expiré ou invalide |
| `403` | Rôle insuffisant ou compte suspendu |
| `404` | Ressource introuvable |
| `409` | Conflit (email déjà utilisé, créneau déjà pris…) |
| `500` | Erreur interne serveur |

**Format d'erreur standard**
```json
{
  "status": 403,
  "message": "Accès refusé",
  "timestamp": "2026-08-13T10:00:00"
}
```

---

## Légende

| Symbole | Signification |
|---------|--------------|
| 🔒 | Requiert un JWT valide (`Authorization: Bearer <token>`) |
| *(CLIENT)* | Rôle CLIENT requis |
| *(LAWYER)* | Rôle LAWYER requis |
| *(ADMIN)* | Rôle ADMIN requis |
| *(public)* | Pas d'authentification requise |