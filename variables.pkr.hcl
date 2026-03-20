variable "ubuntu_iso_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "sha256:931dba2bec09d574f032485bda386c664481ef01208371957af28fad40bc7f2d"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "disk_size" {
  type    = string
  default = "20480"
}

variable "jenkins_admin_user" {
  type    = string
  default = "sherpa"
}

variable "jenkins_admin_password" {
  type      = string
  default   = "Everest1953!"
  sensitive = true
}
