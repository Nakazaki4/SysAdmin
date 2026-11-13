packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1"
    }
  }
}

source "virtualbox-iso" "debian" {
  guest_os_type = "Debian_64"
  iso_url       = "/home/nakazaki/Downloads/debian-13.7.0-amd64-netinst.iso"
  iso_checksum  = "sha256:a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355"

  disk_size = 15360   # MB
  memory    = 1024
  cpus      = 1
  headless  = true

  http_directory = "http"
  boot_wait      = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "hostname=sysadmin-vm domain=local<enter>"
  ]

  ssh_username     = "vagrant"
  ssh_password     = "vagrant"
  ssh_timeout      = "30m"
  shutdown_command = "sudo shutdown -P now"

  guest_additions_mode = "disable"
}

build {
  sources = ["source.virtualbox-iso.debian"]

  # Install Vagrant's insecure key so "vagrant ssh" works on first boot
  provisioner "shell" {
    inline = [
      "mkdir -p /home/vagrant/.ssh",
      "curl -fsSL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub -o /home/vagrant/.ssh/authorized_keys",
      "chmod 700 /home/vagrant/.ssh && chmod 600 /home/vagrant/.ssh/authorized_keys"
    ]
  }

  post-processor "vagrant" {
    output = "debian-lvm.box"
  }
}

