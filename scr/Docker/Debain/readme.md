# Debian development container

This Compose project builds a Debian container with `sudo`, `curl`, and `ping`. The folder is named `Debain` in this repository; keep that spelling in paths unless you rename the directory and update any references to it.

The image creates `user1` with sudo access, sets `/home/user1/pro` as a prepared workspace, and uses `user1` as the default container account.

## Start

Run from this directory (`scr/Docker/Debain`). Linux users may prefix Docker commands with `sudo` if required by their Docker setup. On Windows PowerShell with Docker Desktop in Linux-container mode, omit `sudo`.

```sh
docker compose config
docker compose up -d --build
docker compose ps
```

## Use and manage

```sh
docker compose exec debian-box bash
docker compose stop       # stop while keeping the container
docker compose start      # restart the stopped container
docker compose down       # remove the container and network
```

There are no bind mounts or named volumes in this example, so files written only inside the container are lost when you remove it with `docker compose down`. Add a bind mount in `compose.yaml` if you need to keep project files on the host. Compose resolves relative host paths from this file's directory.

## Credentials

The Dockerfile currently sets the example password `hipassword` for `user1`. Change it before using the image for anything beyond a disposable local container; the password is stored in the image build history. Do not expose this sample container to an untrusted network.
