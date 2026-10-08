# OCI instance (4 OCPU / 24 GB)

One `VM.Standard.A1.Flex` (Ampere, arm64) instance running Oracle Linux 10, with Docker installed by cloud-init. It sits in a new VCN with a public subnet. Ports 22, 80 and 443 are open.

## Setup
1. `brew install terraform oci-cli`
2. `oci setup config`, then upload the generated public API key in the OCI console.
3. `cp terraform.tfvars.example terraform.tfvars` and fill in `tenancy_ocid` and `region`. Set `ssh_allowed_cidr` to your own IP.
4. `terraform init && terraform plan && terraform apply`

## Verify
```
ssh opc@$(terraform output -raw public_ip)
cloud-init status --wait
docker run --rm hello-world
nproc && free -g
```

## Disk
The OL10 image only lays out ~47 GB of the boot volume. `cloud-init.yaml` runs `/usr/libexec/oci-growfs -y` on first boot (non-fatal) to grow root into the rest. Check with `df -h /` and `grep growfs /var/log/cloud-init-output.log`. On an existing instance, run `sudo /usr/libexec/oci-growfs -y`.

## Oracle Linux 10 primer
Oracle Linux is a RHEL-compatible distro (same family as Rocky, Alma and CentOS Stream), so RHEL docs and answers generally apply. If you know Ubuntu or Debian, the main differences are below.

**Users and access**
- The default user is `opc` (not `ubuntu`), with passwordless `sudo`. Login is by the SSH key set in `ssh_public_key_path`.
- Log in as `opc` and use `sudo` rather than logging in as `root`.

**Packages**
| Task | Command |
|---|---|
| Install / remove | `sudo dnf install <pkg>` / `sudo dnf remove <pkg>` |
| Update everything | `sudo dnf upgrade` |
| Search / info | `dnf search <term>` / `dnf info <pkg>` |
| Which package owns a file | `dnf provides /path/to/file` |
| List installed | `rpm -qa` or `dnf list installed` |
| Repo config | `/etc/yum.repos.d/*.repo` (`dnf repolist`) |

- `dnf` is the package manager (`yum` is an alias for it). Packages are `.rpm` files, not `.deb`, and there is no `apt`.
- Software comes from Oracle's `ol10_*` repos. Third-party repos, like Docker's, are `.repo` files in `/etc/yum.repos.d/`.
- Some Oracle repos (e.g. `ol10_ksplice`) can be unreachable, which is why the bootstrap lets other repos be skipped. Toggle a repo for one command with `--enablerepo=<id>` / `--disablerepo=<id>`.
- `dnf-automatic` can apply security updates unattended. It is not enabled here.

**Services (systemd)**
- `sudo systemctl status|start|stop|restart|enable|disable <unit>`. `enable --now` does enable plus start.
- Logs go to the journal: `journalctl -u <unit> -f`, `journalctl -b` (this boot), `journalctl -p err`.

**Directory layout**
| Path | What it is |
|---|---|
| `/etc` | System config (`/etc/yum.repos.d`, `/etc/ssh/sshd_config`, `/etc/docker`) |
| `/var/log` | Logs (`/var/log/cloud-init-output.log`, `/var/log/messages`) |
| `/var/lib` | Service state (`/var/lib/docker`, `/var/lib/cloud`) |
| `/usr/bin`, `/usr/sbin` | Installed programs. `/bin` and `/sbin` are symlinks to these |
| `/usr/local/sbin`, `/usr/local/bin` | Things you add by hand (the Docker bootstrap script lives here) |
| `/opt` | Self-contained third-party software |
| `/home/opc` | Your home directory |
| `/boot`, `/boot/efi` | Kernel and bootloader (UEFI) |
| `/var/oled` | Oracle Linux Enhanced Diagnostics data, on its own 20 GB volume |
| `/tmp`, `/run` | Scratch space. `/run` is RAM-backed and cleared on reboot |

**Storage**
- Disks use LVM. Volume group `ocivolume` holds the logical volumes `root` (`/`) and `oled` (`/var/oled`), both formatted XFS. See `lsblk`, `sudo vgs`, `sudo lvs`.
- Grow a filesystem with `oci-growfs`, not `resize2fs` (XFS can only grow, never shrink).

**Network and firewall**
- The host firewall is `firewalld`, on top of the OCI security list. Opening a port needs both. Example: `sudo firewall-cmd --permanent --add-port=8080/tcp && sudo firewall-cmd --reload`.
- Check what is open with `sudo firewall-cmd --list-all`, and what is listening with `sudo ss -tlnp`.

**Security**
- SELinux is enforcing by default. If a service works as root but is denied otherwise, check `sudo ausearch -m avc -ts recent` before turning SELinux off. Bind mounts into containers usually need the `:z` suffix, like `-v /data:/data:z`.
- The kernel is Oracle's UEK (`uname -r`). Reboot after kernel updates (`sudo dnf needs-restarting -r` tells you if you need to).

**Architecture**
- This is an arm64 (`aarch64`) machine. Docker images must have an arm64 variant (most official ones do), and prebuilt x86-only binaries will not run.

## Docker bootstrap and troubleshooting
Docker is installed by `/usr/local/sbin/docker-bootstrap.sh` (written by `cloud-init.yaml`). It waits for the network, retries, verifies the Docker repo has `gpgcheck=1` and that the GPG key fingerprint is `060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`, installs Docker, enables it at boot, and writes `/var/lib/cloud/docker-bootstrap.done` only after `docker --version` and `systemctl is-enabled docker` both pass. On failure it exits non-zero and logs `docker-bootstrap: FAILED: ...` to `/var/log/cloud-init-output.log`. Note `cloud-init status` can still say `done` with no errors, so check the marker file:
```
ls /var/lib/cloud/docker-bootstrap.done && docker --version && systemctl is-enabled docker
grep docker-bootstrap /var/log/cloud-init-output.log
```

### Why the first instance had no Docker (root cause)
Evidence, read-only, from `/var/log/cloud-init-output.log` on the existing instance (Oracle Linux 10.2 aarch64, cloud-init 24.4), `modules:final` at ~52 s uptime. The old `runcmd` was a flat list with no wait, retry or error handling:
- `dnf -y install dnf-plugins-core`: `Curl error (7): Could not connect to server for https://yum.us-ashburn-1.oci.oraclecloud.com/.../ksplice/...repomd.xml [Failed to connect ... after 3 ms]`, then `Error: Failed to download metadata for repo 'ol10_ksplice'`.
- `dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo`: `Curl error (7): Could not connect to server for https://download.docker.com/linux/rhel/docker-ce.repo [Failed to connect ... after 0 ms]` and `Error: Configuration of repo failed`. The Docker repo file was never created.
- `dnf -y remove podman buildah runc || true`: `No match for argument` for all three (not installed, so not a conflict).
- `systemctl enable --now docker`: `Failed to enable unit: Unit docker.service does not exist`. `usermod -aG docker opc`: `group 'docker' does not exist`.
- `cloud-init status` still reported `done`, `errors: []`, so the failure was silent.

Confirmed: outbound HTTPS connections failed immediately at that point in boot, the Docker repo was never added, so Docker never installed. Today the same box reaches `download.docker.com` (HTTP 200) and the VCN allows all egress, so steady-state networking is fine.

Hypothesis (not confirmed): the network was not yet usable when `runcmd` ran (a boot-time race). The immediate (0-3 ms) connection failures fit this, but `/var/log/cloud-init.log` is root-only and was not read, and the exact result of the `docker-ce` install line could not be matched to a command. Not verifiable without booting a new instance. The fix (wait for network, retries, fail loudly) targets this, and the loud failure and marker make any other cause visible on the next boot.

### Docker group (follow-up)
As in the previous cloud-init, the bootstrap still runs `usermod -aG docker opc`. Membership of the `docker` group is root-equivalent on the host. Left unchanged because this job does not change privileges; flagged as a follow-up for a hardening PRD.

## Tests
`PY=python3 tests/test_bootstrap.sh` (needs pyyaml) runs stub-based tests of the script (unreachable repo, failing `docker --version` / `is-enabled`, bad fingerprint, `gpgcheck=0`, marker only on success). This is not a real boot. Also: `shellcheck`, and validate `cloud-init.yaml` with `cloud-init schema --config-file cloud-init.yaml --annotate` (or `tests/validate_schema.py`).

## Notes
- "Out of host capacity" on apply is common for A1. Try another `availability_domain_index` or retry later.
- Images are arm64, so use arm64 or multi-arch container images.
