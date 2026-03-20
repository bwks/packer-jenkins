# packer-jenkins

Packer build that produces a Ubuntu 24.04 LTS QCOW2 base image with Jenkins LTS
pre-installed and configured. Designed for Libvirt/KVM/QEMU deployments using
cloud-init NoCloud.

## What's in the image

| Component | Detail |
|-----------|--------|
| Base OS | Ubuntu 24.04 LTS (Noble) |
| Jenkins | LTS (current stable at build time) |
| Java | OpenJDK 21 |
| Disk | 20 GB QCOW2, sparsified |
| Admin user | configurable via variables (default: `sherpa`) |

### Pre-installed plugins

| Plugin | Purpose |
|--------|---------|
| git | Git SCM integration |
| workflow-aggregator | Pipeline (declarative + scripted) |
| pipeline-stage-view | Pipeline stage visualisation |
| blueocean | Modern Pipeline UI |
| docker-workflow | Docker steps in pipelines |
| docker-plugin | Docker agent provisioning |
| credentials-binding | Bind credentials to env vars |
| ssh-agent | SSH key injection for builds |
| matrix-auth | Fine-grained permissions |
| role-strategy | Role-based access control |
| github | GitHub webhook/status integration |
| github-branch-source | Multi-branch pipelines from GitHub |
| pipeline-github-lib | Shared pipeline libraries from GitHub |
| timestamper | Timestamps in build logs |
| ws-cleanup | Workspace cleanup post-build |
| build-timeout | Kill hung builds automatically |
| email-ext | Flexible email notifications |
| mailer | Simple email notifications |
| configuration-as-code | Jenkins config as YAML (JCasC) |
| job-dsl | Programmatic job creation |
| ansicolor | ANSI colour in build logs |
| junit | JUnit test result publishing |
| htmlpublisher | Publish HTML reports |
| slack | Slack notifications |
| sonar | SonarQube scanner integration |
| ansible | Ansible playbook build steps |
| nodejs | Node.js tool installer |

## Requirements

| Tool | Min version | Install |
|------|-------------|---------|
| Packer | 1.9+ | https://developer.hashicorp.com/packer/install |
| qemu-system-x86_64 | 6.x+ | `apt install qemu-system-x86` |
| qemu-img | 6.x+ | included with qemu-utils |
| cloud-localds | any | `apt install cloud-image-utils` |

The QEMU plugin for Packer is installed automatically by `packer init`.

KVM acceleration is used if `/dev/kvm` is available and writable. Without it the
build falls back to TCG emulation and will be significantly slower.

## Quick start

```bash
# 1. Clone
git clone https://github.com/bwks/packer-jenkins.git
cd packer-jenkins

# 2. Build the image (~10 minutes with KVM)
packer build .

# 3. Test it
bash test/test.sh
```

The output image is written to `output/jenkins-base.qcow2`.

## Configuration

Variables can be overridden on the command line or via a `.pkrvars.hcl` file.

```bash
packer build \
  -var="jenkins_admin_user=admin" \
  -var="jenkins_admin_password=s3cr3t" \
  -var="output_dir=/srv/images" \
  .
```

Or create `override.pkrvars.hcl` (already gitignored):

```hcl
jenkins_admin_user     = "admin"
jenkins_admin_password = "s3cr3t"
output_dir             = "/srv/images"
disk_size              = "40960"
```

Then build with:

```bash
packer build -var-file=override.pkrvars.hcl .
```

### All variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ubuntu_iso_url` | Ubuntu 24.04 cloud image URL | Source image |
| `ubuntu_iso_checksum` | sha256 of above | Source image checksum |
| `jenkins_admin_user` | `sherpa` | Jenkins admin username |
| `jenkins_admin_password` | `Everest1953!` | Jenkins admin password |
| `output_dir` | `output` | Directory for the output image |
| `disk_size` | `20480` | Disk size in MiB (20 GB) |

## Testing

The test script boots the image in QEMU, waits for Jenkins to come up, and
checks:

- Login page returns HTTP 200
- Admin credentials authenticate successfully
- Key plugins are installed and active
- Jenkins is not in setup wizard mode

```bash
bash test/test.sh
```

For manual inspection (boots Jenkins and leaves it running):

```bash
bash test/test.sh --run
# Jenkins available at http://localhost:18080/
# Ctrl+C to stop
```

## Deploying with libvirt

Create a cloud-init seed ISO for your deployment, then define the domain.
The image should be copied (or used as a backing store) rather than used
directly so the original is not modified.

```bash
# Create a writable overlay
qemu-img create -f qcow2 \
  -b /path/to/jenkins-base.qcow2 \
  -F qcow2 \
  /var/lib/libvirt/images/jenkins-01.qcow2 \
  20G

# Create cloud-init seed
cat > user-data <<'EOF'
#cloud-config
hostname: jenkins-01
EOF
cloud-localds seed.iso user-data

# Boot with virsh / virt-install or add to your libvirt XML
virt-install \
  --name jenkins-01 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/jenkins-01.qcow2,format=qcow2 \
  --disk path=seed.iso,device=cdrom \
  --os-variant ubuntu24.04 \
  --import \
  --noautoconsole
```

Jenkins will be available on port 8080 of the VM's IP once it boots (~60s).

## Project structure

```
.
├── jenkins.pkr.hcl       # Packer template (source + build blocks)
├── variables.pkr.hcl     # Variable declarations and defaults
├── http/
│   ├── user-data         # Cloud-init config for the Packer build VM
│   └── meta-data         # Cloud-init metadata for the Packer build VM
├── scripts/
│   ├── 01-base.sh        # System update and base packages
│   ├── 02-java.sh        # OpenJDK 21 installation
│   ├── 03-jenkins.sh     # Jenkins install, plugin bake, admin setup
│   └── 04-cleanup.sh     # Apt cache, logs, SSH keys, cloud-init reset
└── test/
    ├── test.sh           # Automated test + --run interactive mode
    ├── user-data         # Cloud-init config for test/run boots
    └── meta-data         # Cloud-init metadata for test/run boots
```

## Rebuilding after changes

The Ubuntu cloud image is cached in `packer_cache/` after the first download.
Subsequent builds skip the download.

```bash
# Force a full rebuild including re-download
packer build -force .
```
