# NAS

The lab stack ships as one image, `yuzuholic/cardea`: a launcher that carries
`lab/docker-compose.yml` and a current docker compose, and starts the stack's official images
next to itself on the NAS's docker engine.

| File | What it is |
|---|---|
| `compose.yml` | What runs on the NAS: the single `cardea` service, with every setting declared. |
| `.env.example` | The values for those settings. Copy to `.env` beside `compose.yml`. |
| `lab/docker-compose.yml` | The stack itself, baked into the image. |
| `Dockerfile`, `cardea.sh` | The launcher. |

Build and push (the NAS is x86, this Mac is arm, so build both):

    docker buildx build --platform linux/amd64,linux/arm64 -t yuzuholic/cardea:latest --push nas/

Services, ports, secrets and backups: https://yuzuholic.github.io/cardea/docs/nas
(source: `docs/content/docs/nas.mdx`).
