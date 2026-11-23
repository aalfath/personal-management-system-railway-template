# Personal Management System on Railway

This repo is the source of a Railway template for [Personal Management System](https://github.com/Volmarg/personal-management-system) (PMS) by Volmarg. PMS is a self-hosted web app for personal data: notes, todos, goals, contacts, passwords, payments, calendar, travel ideas, files and images.

## What it deploys

| Service | Folder | Built from | Volume |
|---|---|---|---|
| `Personal Management System` (public) | `app/` | `php:8.4.28-fpm` (pinned by digest) + PMS **v2.1.0** backend and frontend release commits (pinned by commit and sha256), nginx in front | `/data` |
| `MariaDB` (private) | `mariadb/` | `mariadb:11.8.9` (pinned by digest) | `/var/lib/mysql` |

PMS publishes no container image, so `app/Dockerfile` builds one from the upstream v2.1.0 release:

- The Vue frontend is served at `/` and the Symfony API at `/api` on the same domain.
- Health check: `/healthz`.
- First boot generates this instance's JWT key pair and its encryption key for the Passwords module, both on the `/data` volume. Upstream's install ships the same keys to everyone; this template does not use them. The frontend gets this instance's JWT public key on every boot.
- First boot creates the owner account from the variables below. Public registration is always blocked: `/api/register-user` only answers from inside the container.
- Database migrations run on every boot.
- Mail is off (`MAILER_DSN=null://null`). Set `MAILER_DSN` yourself if you want PMS's mail features.
- Uploads up to 100 MB.

## Variables

| Service | Variable | Value |
|---|---|---|
| app | `PMS_ADMIN_EMAIL` | **Asked at deploy.** Your login email. |
| app | `PMS_ADMIN_PASSWORD` | Generated. Your login password (see the service's Variables tab). |
| app | `PMS_LOCK_PASSWORD` | Generated. Second password that unlocks PMS's locked (hidden) records. |
| app | `APP_SECRET` | Generated. Symfony secret, also the JWT key passphrase. |
| app | `DB_HOST`, `DB_PASSWORD` | References to the MariaDB service. |
| app | `PORT` | `8080` |
| MariaDB | `MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD` | Generated. |
| MariaDB | `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` (clean shutdown on redeploy) |

`PMS_ADMIN_EMAIL`, `PMS_ADMIN_PASSWORD` and `PMS_LOCK_PASSWORD` are only used to create the owner account on the first boot. To change them later, use PMS's own user settings.

**Back up the `/data` volume.** `/data/config/encryption.yaml` holds the key for the Passwords module: without it, the stored passwords can't be decrypted. Don't change `APP_SECRET` after the first boot, because it protects the JWT key on `/data/jwt`.

## Known upstream behaviour

- Uploaded images smaller than about 7 KB are rejected by PMS's own upload check.
- PHP 8.4 deprecation notices are kept out of API responses (`display_errors=Off`) and go to the logs only.

## Updates

Both services build from this repo's `main` branch. When a new PMS version is merged here, everyone who deployed the template sees an "update available" notice on Railway and chooses when to apply it. Read [CHANGELOG.md](CHANGELOG.md) first: breaking changes are listed at the top of each entry.

## License

The wrapper files in this repo are MIT. Personal Management System is MIT-licensed by Volmarg.
