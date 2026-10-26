# NAS

`lab/docker-compose.yml` is a copy of what runs on the NAS at `/Volumes/docker/lab`
(`/mnt/.../docker/lab` from the NAS's own side). Edit it there, then copy it back here —
this directory is the record, not the deployment.

    docker compose up -d
    docker compose exec basic-memory basic-memory project create homelab /app/kb/homelab

## Secrets

Live in `.env` beside the compose file on the NAS, never in this repo. Nothing in the
compose file has a working fallback, so a missing secret stops that service rather than
quietly starting it with a published default.

If you ever need to regenerate them: `openssl rand -base64 36` for passwords,
`openssl rand -hex 32` for `ENCRYPTION_KEY`. The three
`LANGFUSE_S3_*_SECRET_ACCESS_KEY` values must all equal `MINIO_ROOT_PASSWORD`, and
`DATABASE_URL` embeds `POSTGRES_PASSWORD`.

## Exposure

| Service | Port | Reachable from |
|---|---|---|
| basic-memory | 8766 | LAN |
| langfuse-web | 3000 | LAN |
| minio | 9090 | LAN |
| clickhouse, postgres, redis, langfuse-worker | — | NAS localhost only |

Basic Memory has **no auth at all** on 8766. It is LAN-only by intent. Do not route it
through the Cloudflare tunnel without Cloudflare Access in front of it.

MinIO's 9090 has to stay LAN-reachable because the browser uploads media straight to it,
which is why `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` points at `nas.local` and not `localhost`.

## Backups

Langfuse's compose has no high availability and no backups. The data that matters is the
`langfuse_postgres_data` and `langfuse_clickhouse_data` volumes, plus `kb/`. Nothing here backs them up for you.

The vaults live in `kb/` beside the compose file. They must be writable by uid 1000
(`appuser`) or Basic Memory starts and then stops serving, with no obvious error:

    chown -R 1000:1000 kb

The SQLite index is in the `basic_memory_data` named volume, not in `kb/`, because SQLite
on an SMB or NFS share corrupts. Obsidian reads `kb/` over SMB, which is fine — that is
plain markdown.

## Pins

Upstream Langfuse floats `langfuse:4`, `postgres:17` and `redis:7`, and ships MinIO with no
tag at all. All four are pinned to exact versions here; MinIO is pinned by digest because
Chainguard publishes no version tags on the free tier — if that digest ever stops pulling,
re-resolve `cgr.dev/chainguard/minio:latest` and update it.
