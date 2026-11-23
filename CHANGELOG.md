# Changelog

Breaking changes come first in each entry. Read the entry before you apply an update on Railway.

## 2.1.0-railway.1 (2026-11-23)

First release of the template.

- Personal Management System v2.1.0 (backend `6bbeb02`, frontend `f16eb6d`) on `php:8.4.28-fpm@sha256:495ab947…`, with nginx in the same service.
- MariaDB 11.8.9 LTS (`mariadb:11.8.9@sha256:e1d5495f…`), data in `/var/lib/mysql/data`.
- Per-instance JWT key pair and Passwords encryption key, generated on the first boot on the `/data` volume.
- Owner account created on the first boot. Public registration blocked.
