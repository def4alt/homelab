#!/usr/bin/env bash
set -euo pipefail

dokploy_image="dokploy/dokploy:v0.29.12"
postgres_image="postgres:16"
traefik_image="traefik:v3.6.7"

if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]]; then
  docker swarm init \
    --advertise-addr 192.168.88.189 \
    --default-addr-pool 172.30.0.0/16 \
    --default-addr-pool-mask-length 24
fi

if ! docker network inspect dokploy-network >/dev/null 2>&1; then
  docker network create --driver overlay --attachable dokploy-network
fi

if ! docker secret inspect dokploy_postgres_password >/dev/null 2>&1; then
  openssl rand -hex 32 | docker secret create dokploy_postgres_password -
fi

if ! docker secret inspect dokploy_auth_secret >/dev/null 2>&1; then
  openssl rand -hex 32 | docker secret create dokploy_auth_secret -
fi

install -d -m 0750 /etc/dokploy

if ! docker service inspect dokploy-postgres >/dev/null 2>&1; then
  docker service create \
    --name dokploy-postgres \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --env POSTGRES_USER=dokploy \
    --env POSTGRES_DB=dokploy \
    --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
    --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
    --mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data \
    "${postgres_image}"
fi

if docker service inspect dokploy >/dev/null 2>&1; then
  docker service update --image "${dokploy_image}" dokploy
else
  docker service create \
    --name dokploy \
    --replicas 1 \
    --network dokploy-network \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
    --mount type=volume,source=dokploy,target=/root/.docker \
    --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
    --secret source=dokploy_auth_secret,target=/run/secrets/dokploy_auth_secret \
    --publish published=3000,target=3000,mode=host \
    --update-parallelism 1 \
    --update-order stop-first \
    --constraint 'node.role==manager' \
    --env RELEASE_TAG=latest \
    --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
    --env BETTER_AUTH_SECRET_FILE=/run/secrets/dokploy_auth_secret \
    "${dokploy_image}"
fi

for _ in $(seq 1 30); do
  [[ -f /etc/dokploy/traefik/traefik.yml ]] && break
  sleep 2
done

if [[ ! -f /etc/dokploy/traefik/traefik.yml ]]; then
  echo "Dokploy did not generate its Traefik configuration" >&2
  exit 1
fi

docker pull "${traefik_image}"
if docker container inspect dokploy-traefik >/dev/null 2>&1; then
  current_image="$(docker container inspect --format '{{.Config.Image}}' dokploy-traefik)"
  if [[ "${current_image}" != "${traefik_image}" ]]; then
    docker rm --force dokploy-traefik
  fi
fi

if ! docker container inspect dokploy-traefik >/dev/null 2>&1; then
  docker run -d \
    --name dokploy-traefik \
    --restart always \
    --volume /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
    --volume /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
    --volume /var/run/docker.sock:/var/run/docker.sock:ro \
    --publish 9080:80/tcp \
    --publish 9443:443/tcp \
    --publish 9443:443/udp \
    "${traefik_image}"
  docker network connect dokploy-network dokploy-traefik
fi
