# CLAUDE.md

## Project

Packer build for a Jenkins LTS base cloud image targeting Libvirt/KVM/QEMU NoCloud.
Source: Ubuntu 24.04 (noble) cloud image. Output: `output/jenkins-base.qcow2`.
GitHub: https://github.com/bwks/packer-jenkins — working branch: `feature/packer-jenkins-build`.

## Key commands

```bash
packer build .              # build the image (clears output/ first if it exists)
bash test/test.sh           # automated tests against the built image
bash test/test.sh --run     # boot interactively at http://localhost:18080/
```

`output/` must not exist before building — remove it first if re-running.

## Known gotchas

**Jenkins GPG key** — `jenkins.io-2023.key` does not contain key `7198F4B714ABFC68`.
Fetch it from the Ubuntu keyserver instead (see `scripts/03-jenkins.sh`).

**Jenkins auto-starts on apt install** — the apt post-hook starts Jenkins before
groovy init scripts exist. The provisioner stops Jenkins immediately after install,
sets everything up, then starts it fresh. Do not move the `systemctl stop` call.

**cloud-init exit code** — `cloud-init status --wait` exits 2 on non-fatal errors.
The Packer shell provisioner uses `valid_exit_codes = [0, 2]` to handle this.

**virt-sparsify** — fails in nested VM environments (supermin/libguestfs).
Use `qemu-img convert -f qcow2 -O qcow2 -c` instead.

## Credentials (baked into image)

- Jenkins admin: `sherpa` / `Everest1953!`
- Build-time SSH user: `packer` / `packer` (removed during cleanup)

## Structure

```
jenkins.pkr.hcl       # Packer source + build blocks
variables.pkr.hcl     # All variables with defaults
http/                 # Cloud-init for the Packer build VM (NoCloud seed)
scripts/
  01-base.sh          # System update + base packages
  02-java.sh          # OpenJDK 21
  03-jenkins.sh       # Jenkins install, plugins (PIMT), groovy init, verify
  04-cleanup.sh       # Apt cache, logs, SSH keys, cloud-init reset
test/
  test.sh             # Automated tests + --run interactive mode
  user-data           # Cloud-init for test/run boots
  meta-data           # Cloud-init metadata for test/run boots
```

## Plugins

Managed in `scripts/03-jenkins.sh` as a heredoc passed to the Plugin Installation
Manager Tool (PIMT). PIMT resolves dependencies and runs without Jenkins running.
The test script checks a representative subset — update `check_plugin` calls there
when adding plugins.
