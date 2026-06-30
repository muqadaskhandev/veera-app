# Verra API (Vapor + PostgreSQL)

Local backend for the VerraOS iOS app.

## Prerequisites

- Swift 6+
- Homebrew PostgreSQL 17

```bash
brew install postgresql@17 vapor
brew services start postgresql@17
createdb verra_dev
```

## Environment

Copy `.env.example` to `.env` and set your macOS username:

```bash
cp .env.example .env
```

Required variables:

| Variable | Purpose |
|----------|---------|
| `DATABASE_*` | PostgreSQL connection |
| `JWT_SECRET` | Signs access tokens |
| `APPLE_CLIENT_ID` | Sign in with Apple audience check |
| `ADMIN_SETUP_SECRET` | Required secret to create admin accounts |
| `AWS_ACCESS_KEY_ID` | IAM key for Amazon SES |
| `AWS_SECRET_ACCESS_KEY` | IAM secret for Amazon SES |
| `AWS_REGION` | SES region (default `us-east-1`) |
| `SES_FROM_EMAIL` | Verified sender address in SES |
| `SES_FROM_NAME` | Optional display name (default `Verra`) |
| `PASSWORD_RESET_URL` | Base URL for password reset links |

## Email (Amazon SES)

Verification codes and password reset emails are sent through **Amazon SES** when these env vars are set:

```bash
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
SES_FROM_EMAIL=noreply@yourdomain.com
SES_FROM_NAME=Verra
```

**AWS setup checklist:**

1. Verify your sender email or domain in the SES console
2. Create an IAM user with permission to send email. Attach this policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
```

Use the access key / secret from that IAM user in `.env` (not the root account keys).

3. Verify your sender email or domain in the SES console **in the same region** as `AWS_REGION` (e.g. `eu-north-1`).
4. Add the credentials to `.env` and restart the server

Without SES configured, development mode logs email content to the terminal and the API may return `devCode` for local testing.


```bash
cd backend
export $(grep -v '^#' .env | xargs)
swift run backend serve --hostname 127.0.0.1 --port 8080
```

Migrations run automatically on startup.

## Roles

| Role | Description |
|------|-------------|
| `trainer` | Coach account, creates invites, manages clients |
| `client` | Client account, joins via invite code |
| `admin` | Platform admin, user management |

## Auth APIs

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth/register` | No | Email/password sign up |
| POST | `/api/auth/login` | No | Email/password login |
| POST | `/api/auth/apple` | No | Sign in with Apple |
| POST | `/api/auth/refresh` | No | Refresh access token |
| POST | `/api/auth/logout` | No | Revoke refresh token |
| GET | `/api/auth/me` | Bearer | Current user |
| POST | `/api/auth/password/forgot` | No | Request password reset |
| POST | `/api/auth/password/reset` | No | Reset password with token |

### Register trainer

```bash
curl -X POST http://127.0.0.1:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "trainer@verra.test",
    "password": "password123",
    "role": "trainer",
    "displayName": "Jordan Vale"
  }'
```

### Register client (invite required)

```bash
curl -X POST http://127.0.0.1:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "client@verra.test",
    "password": "password123",
    "role": "client",
    "displayName": "Maya Chen",
    "inviteCode": "ECZJPJHA"
  }'
```

### Sign in with Apple

```bash
curl -X POST http://127.0.0.1:8080/api/auth/apple \
  -H "Content-Type: application/json" \
  -d '{
    "identityToken": "<apple-identity-token>",
    "role": "trainer",
    "displayName": "Jordan Vale"
  }'
```

## Onboarding APIs

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/onboarding/invite/validate` | No | Validate client invite code |
| GET | `/api/onboarding/status` | Bearer | Onboarding completion status |
| GET | `/api/onboarding/trainer` | Trainer | Get questionnaire answers |
| POST | `/api/onboarding/trainer` | Trainer | Save questionnaire answers |
| POST | `/api/onboarding/client` | Client | Complete client onboarding |

### Validate invite (client onboarding screen)

```bash
curl -X POST http://127.0.0.1:8080/api/onboarding/invite/validate \
  -H "Content-Type: application/json" \
  -d '{"code":"ECZJPJHA"}'
```

### Save trainer onboarding answers

```bash
curl -X POST http://127.0.0.1:8080/api/onboarding/trainer \
  -H "Authorization: Bearer <accessToken>" \
  -H "Content-Type: application/json" \
  -d '{
    "answers": {
      "coaching_style": "hands_on",
      "client_count": "10_20"
    },
    "markComplete": true
  }'
```

## Invite APIs (trainer)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/invites` | Trainer/Admin | List invite codes |
| POST | `/api/invites` | Trainer/Admin | Create invite code |

## Admin APIs

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/admin/users` | Admin | List all users |
| PATCH | `/api/admin/users/:id/status` | Admin | Activate/deactivate user |

## Data APIs (existing)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/clients` | List clients |
| POST | `/api/clients` | Create client |
| GET | `/api/sessions` | List sessions |
| POST | `/api/sessions` | Create session |

## Database schema

| Table | Purpose |
|-------|---------|
| `users` | Auth accounts (trainer/client/admin) |
| `auth_sessions` | Refresh token sessions |
| `password_reset_tokens` | Password reset flow |
| `invite_codes` | Client invite codes |
| `trainer_onboarding` | Trainer questionnaire answers |
| `trainers` | Trainer profiles |
| `clients` | Client roster |
| `sessions` | Scheduled appointments |
| `conversations` | Message threads |
| `messages` | Chat messages |

## iOS integration (no UI changes yet)

The iOS app can call these endpoints when ready:

- Trainer register screen → `POST /api/auth/register` with `role: trainer`
- Client invite screen → `POST /api/onboarding/invite/validate`
- Client register → `POST /api/auth/register` with `role: client` + `inviteCode`
- Trainer questionnaire → `POST /api/onboarding/trainer`
- Continue with Email → `POST /api/auth/register` or `POST /api/auth/login`
- Sign in with Apple → `POST /api/auth/apple`

Use `Authorization: Bearer <accessToken>` for protected routes.
