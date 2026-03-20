packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "jenkins" {
  # Source image
  iso_url      = var.ubuntu_iso_url
  iso_checksum = var.ubuntu_iso_checksum
  disk_image   = true

  # Output
  output_directory = var.output_dir
  vm_name          = "jenkins-base.qcow2"
  format           = "qcow2"
  disk_size        = var.disk_size

  # Hardware
  accelerator    = "kvm"
  cpus           = 2
  memory         = 4096
  headless       = true
  net_device     = "virtio-net-pci"
  disk_interface = "virtio"

  # Cloud-init NoCloud seed (cidata label makes cloud-init use this as NoCloud datasource)
  cd_files = ["http/user-data", "http/meta-data"]
  cd_label = "cidata"

  # SSH communicator
  ssh_username         = "packer"
  ssh_password         = "packer"
  ssh_timeout          = "15m"
  ssh_handshake_attempts = 30

  # Boot
  boot_wait        = "5s"
  shutdown_command = "sudo shutdown -P now"
}

build {
  name    = "jenkins"
  sources = ["source.qemu.jenkins"]

  # Wait for cloud-init to finish before provisioning
  # Exit code 2 means cloud-init finished with non-fatal errors; still safe to proceed.
  # cloud-init exit code 2 = finished with non-fatal errors; safe to proceed.
  provisioner "shell" {
    valid_exit_codes = [0, 2]
    inline = [
      "echo 'Waiting for cloud-init...'",
      "sudo cloud-init status --wait",
      "echo 'Cloud-init complete'"
    ]
  }

  # Base system update and packages
  provisioner "shell" {
    script          = "scripts/01-base.sh"
    execute_command = "sudo bash -c '{{ .Vars }} {{ .Path }}'"
  }

  # Java
  provisioner "shell" {
    script          = "scripts/02-java.sh"
    execute_command = "sudo bash -c '{{ .Vars }} {{ .Path }}'"
  }

  # Jenkins install, plugin bake, admin setup
  provisioner "shell" {
    script          = "scripts/03-jenkins.sh"
    execute_command = "sudo bash -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = [
      "JENKINS_ADMIN_USER=${var.jenkins_admin_user}",
      "JENKINS_ADMIN_PASSWORD=${var.jenkins_admin_password}",
    ]
    timeout = "30m"
  }

  # Cleanup / image prep
  provisioner "shell" {
    script          = "scripts/04-cleanup.sh"
    execute_command = "sudo bash -c '{{ .Vars }} {{ .Path }}'"
  }

  # Sparsify: convert to a new compressed/sparse QCOW2 and replace the original.
  # Using qemu-img convert instead of virt-sparsify (virt-sparsify requires
  # nested KVM which may not be available on all build hosts).
  post-processor "shell-local" {
    inline = [
      "echo 'Sparsifying image...'",
      "qemu-img convert -f qcow2 -O qcow2 -c ${var.output_dir}/jenkins-base.qcow2 ${var.output_dir}/jenkins-base-sparse.qcow2",
      "mv ${var.output_dir}/jenkins-base-sparse.qcow2 ${var.output_dir}/jenkins-base.qcow2",
      "echo 'Image size:' $(du -sh ${var.output_dir}/jenkins-base.qcow2 | cut -f1)"
    ]
  }
}
