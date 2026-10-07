# Windows VM with Docker Compose

This Compose project runs a Windows virtual machine inside the `dockurr/windows` container. The container still needs hardware virtualization; it is not a lightweight Windows container.

## Host requirements and compatibility

- Linux hosts (including Debian, Ubuntu, Arch, Kali, and other distributions) need Docker Engine or Podman with KVM enabled and access to `/dev/kvm`.
- Windows hosts need Windows 11 with Docker Desktop or Podman Desktop and nested virtualization enabled. Docker Desktop on Windows 10, macOS, and Docker Desktop on Linux do not provide the required KVM access and are not supported by this image.
- This Compose file uses the standard `dockurr/windows` image; use the upstream ARM image and instructions for an ARM64 Windows guest.
- The upstream minimum is 2 GB of available RAM and 32 GB of free disk space. This Compose file assigns 4 GB RAM and 2 CPU cores to the guest and creates a 64 GB virtual disk, so plan for those configured amounts plus host/runtime overhead. Lower `RAM_SIZE` only if your host is memory constrained and the guest workload supports it.

See the [upstream requirements](https://github.com/dockur/windows#requirements) before troubleshooting virtualization.

## Choose a Windows ISO

By default, the image downloads and installs Windows 11 Pro. To use your own ISO:

1. Put the ISO in this folder, beside `compose.yaml` (the `scr/Docker/Window/` directory in this repository).
2. Open `compose.yaml` and uncomment the optional custom ISO volume under `services.windows.volumes`.
3. Replace `Windows_11.iso` with the ISO's exact filename. For example, if the file is named `Win11_24H2_English_x64.iso`, use:

   ```yaml
   - ./Win11_24H2_English_x64.iso:/custom.iso:ro
   ```

The path before the colon is the file on the host; `/custom.iso` is the path inside the container. Compose resolves `./` relative to this `compose.yaml`, not the directory from which you happen to run the command. The custom ISO overrides `VERSION`. Use installation media you are authorized to use. ISO files and `win_storage/` are excluded from Git by this folder's `.gitignore`.

## Start and manage the VM

Run these commands from this folder. On Linux, add `sudo` if your account does not have permission to use Docker; on Windows PowerShell, use the commands as shown without `sudo`.

```sh
docker compose config
docker compose up -d
docker compose ps
docker compose logs -f windows
```

Open `http://localhost:8006` in a browser to view the installer and desktop. The web viewer is also available from another machine at `http://HOST_ADDRESS:8006` if the host firewall permits it. RDP is exposed on port `3389`.

```sh
docker compose stop       # stop the VM, preserving its disk
docker compose start      # start the stopped VM
docker compose down       # remove the container/network; preserve ./win_storage
```

The `./win_storage` directory contains the persistent Windows disk. Back it up before changing or deleting it. Removing that directory permanently deletes the VM and its data; it is not required for a normal restart or Compose update.

## Adjust resources and credentials

Edit `compose.yaml` before starting the VM:

- `RAM_SIZE` is memory assigned to the guest. Reduce it only if the Windows release and workload can run with less; reserve memory for the host.
- `CPU_CORES` controls guest CPU cores.
- `DISK_SIZE` controls the virtual disk capacity. The default here is `64G` for Windows 11. Increasing an existing disk does not automatically expand the Windows partition.
- Change `USERNAME` and `PASSWORD` from the example values before use. Treat the Compose file as sensitive if you put real credentials in it.

After changing settings for an existing VM, recreate the container with `docker compose up -d --force-recreate`. This keeps `./win_storage`; changing `DISK_SIZE` does not erase or shrink an existing disk.

## Troubleshooting

- `docker compose config` reports a volume error: check the ISO spelling and make sure the file exists beside `compose.yaml`. If you do not use a custom ISO, leave that example line commented out.
- `/dev/kvm` is missing on Linux: enable Intel VT-x/AMD-V in firmware, check nested virtualization if applicable, and confirm `/dev/kvm` exists on the host.
- The VM cannot start: check `docker compose logs --tail=100 windows` and confirm the host has enough free RAM and disk space.
- To verify the resolved Compose settings without starting the VM, run `docker compose config`.
