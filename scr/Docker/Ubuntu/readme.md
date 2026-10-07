# Ubuntu development container

This Compose project builds an Ubuntu 24.04 development container with `curl` and `ping`. The `user1` account is the default container user and starts in `/home/user1`.

## Start

Run from this directory (`scr/Docker/Ubuntu`). Linux users may prefix Docker commands with `sudo` if required by their Docker setup. On Windows PowerShell with Docker Desktop in Linux-container mode, omit `sudo`.

```sh
docker compose config
docker compose up -d --build
docker compose ps
```

## Use and manage

```sh
docker compose exec ubuntu-box bash
docker compose stop       # stop while keeping the container
docker compose start      # restart the stopped container
docker compose down       # remove the container and network
```

There are no bind mounts or named volumes in this example, so files written only inside the container are lost when you remove it with `docker compose down`. Add a bind mount in `compose.yaml` if you need to keep project files on the host. Compose resolves relative host paths from this file's directory.

## Credentials

The Dockerfile creates `user1` without a password. Do not use this sample as a network-facing service without adding appropriate authentication and access controls.
