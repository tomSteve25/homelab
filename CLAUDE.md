# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A "clone and run" homelab configuration repo. All services are containerized with Docker Compose, targeting ARM64 (Odroid) but compatible with x86_64. Deploy with `sudo ./setup.sh`.

## Commands

```bash
# Full deploy (installs Docker, configures system, launches everything)
sudo ./setup.sh

# Standard Docker Compose operations (run from repo root)
docker compose up -d          # Start all services
docker compose down           # Stop all services
docker compose pull           # Update images
docker compose logs -f <svc>  # Tail logs for a service

# Check Tailscale status
docker exec tailscale-pihole tailscale status
docker exec tailscale-pihole tailscale ip -4
```

## Architecture

### Compose Structure

The root `docker-compose.yml` uses the `include` directive to pull in per-service compose files from `services/*/compose.yml`. Each service directory is self-contained. Shared networks (like `proxy`) are defined at the root level.

### Networking Pattern: Tailscale Sidecar

Services that should be reachable on the Tailnet use a Tailscale container as a network sidecar. The service container sets `network_mode: service:<tailscale-container>` to share the Tailscale container's network namespace. This means the service's ports are bound on the Tailscale interface, not the host.

Key constraints of this pattern:
- The service container cannot use Docker DNS (no container name resolution)
- Ports are exposed on the Tailscale IP, not on `localhost`
- The Tailscale container must be healthy before the service starts

### Reverse Proxy

Traefik (Docker provider, `exposedByDefault: false`) handles HTTPS routing. Services opt in via Docker labels. Cloudflare Tunnel (`cloudflared`) connects to Cloudflare with zero inbound ports. TLS certs are issued via Cloudflare DNS challenge.

### Adding a New Service

1. Create `services/<name>/compose.yml`
2. Add `- path: services/<name>/compose.yml` to the root `docker-compose.yml` `include` list
3. For Traefik routing, add labels and connect to the `proxy` network
4. For Tailnet-only access, use the Tailscale sidecar pattern instead

## Environment

All configuration is in `.env` (created from `.env.example` by setup script). The `.env` file is gitignored. Required variables: `TS_AUTHKEY`, `PIHOLE_PASSWORD`. Cloudflare variables are optional until you need external access via tunnel.
