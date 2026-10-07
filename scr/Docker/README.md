# Docker examples

This folder contains two Linux development-container examples and one Windows virtual-machine example:

| Folder | Image/guest | Compose service | Persistent data |
| --- | --- | --- | --- |
| `Debain/` | Debian Linux | `debian-box` | None by default |
| `Ubuntu/` | Ubuntu 24.04 Linux | `ubuntu-box` | None by default |
| `Window/` | Windows VM using `dockurr/windows` | `windows` | `Window/win_storage/` |

`Debain` and `Window` are the existing directory spellings. Keep them when following these paths.

## Host compatibility

The Debian and Ubuntu examples are ordinary Linux containers. They work with Docker/Podman on Linux and with Docker Desktop configured for Linux containers on Windows or macOS.

The Windows VM has extra virtualization requirements: Linux hosts need KVM; Windows hosts need Windows 11 with nested virtualization enabled. The upstream image does not support Docker Desktop on macOS, Linux, or Windows 10 because those environments do not expose the required KVM interface. Check [Windows VM requirements](https://github.com/dockur/windows#requirements) before starting that example.

## General Compose workflow

Run commands from the selected example's directory, where its `compose.yaml` and Dockerfile (if any) are located:

```sh
docker compose config
docker compose up -d --build
docker compose ps
docker compose logs -f
docker compose stop
docker compose start
docker compose down
```

Use `sudo` on Linux only if your Docker socket requires it. Do not type `sudo` in Windows PowerShell or macOS Terminal. Docker Desktop on Windows should be in Linux-container mode for the Debian and Ubuntu examples. To use a host folder in a Compose bind mount, use a relative path such as `./data:/data`; relative paths are resolved from the Compose file's directory on Linux, Windows, and macOS.

`docker compose down` removes containers and the Compose network. Data in a bind-mounted host folder remains; data stored only in a container's writable layer does not. Back up persistent VM storage before making changes.

## Individual guides

- [Debian development container](Debain/readme.md)
- [Ubuntu development container](Ubuntu/readme.md)
- [Windows VM, custom ISO, and KVM setup](Window/readme.md)
