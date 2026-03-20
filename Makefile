.PHONY: init build test run clean

SHELL        := /bin/bash
OUTPUT_IMAGE := output/jenkins-base.qcow2
JENKINS_PORT := 18080
SSH_PORT     := 12222

init:
	packer init jenkins.pkr.hcl

build: init
	packer build jenkins.pkr.hcl

test: $(OUTPUT_IMAGE)
	bash test/test.sh

# Boot the image interactively for manual inspection.
# Jenkins will be available at http://localhost:$(JENKINS_PORT)/
run: $(OUTPUT_IMAGE)
	@echo "Starting Jenkins VM at http://localhost:$(JENKINS_PORT)/"
	@echo "Press Ctrl+C to stop"
	@qemu-img create -f qcow2 -b $(OUTPUT_IMAGE) -F qcow2 /tmp/jenkins-run.qcow2 20G
	@cloud-localds /tmp/jenkins-run-seed.iso test/user-data test/meta-data
	@qemu-system-x86_64 \
		-m 2048 \
		-smp 2 \
		$(shell test -w /dev/kvm && echo "-enable-kvm") \
		-display none \
		-drive "file=/tmp/jenkins-run.qcow2,format=qcow2,if=virtio" \
		-drive "file=/tmp/jenkins-run-seed.iso,format=raw,if=virtio" \
		-netdev "user,id=net0,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(JENKINS_PORT)-:8080" \
		-device "virtio-net-pci,netdev=net0" || true
	@rm -f /tmp/jenkins-run.qcow2 /tmp/jenkins-run-seed.iso

$(OUTPUT_IMAGE):
	@echo "Image not found. Run 'make build' first."
	@exit 1

clean:
	rm -rf output/
	rm -f /tmp/jenkins-test.qcow2 /tmp/jenkins-test-seed.iso /tmp/jenkins-test-vm.pid
	rm -f /tmp/jenkins-run.qcow2 /tmp/jenkins-run-seed.iso
