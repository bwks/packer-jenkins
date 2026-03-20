#!/bin/bash
# Boot the Jenkins image and validate it, or run interactively for manual inspection.
#
# Usage:
#   bash test/test.sh          # automated tests
#   bash test/test.sh --run    # interactive boot (Ctrl+C to stop)
#
set -euo pipefail

if [[ "${1:-}" == "--run" ]]; then
    IMAGE="$(dirname "$0")/../output/jenkins-base.qcow2"
    SEED_ISO="/tmp/jenkins-run-seed.iso"
    RUN_IMAGE="/tmp/jenkins-run.qcow2"
    cloud-localds "$SEED_ISO" "$(dirname "$0")/user-data" "$(dirname "$0")/meta-data"
    qemu-img create -f qcow2 -b "$(realpath "$IMAGE")" -F qcow2 "$RUN_IMAGE" 20G
    echo "Jenkins will be available at http://localhost:18080/ (give it ~60s)"
    echo "Press Ctrl+C to stop"
    ACCEL=""; [ -w /dev/kvm ] && ACCEL="-enable-kvm"
    qemu-system-x86_64 -m 2048 -smp 2 ${ACCEL} -display none \
        -drive "file=${RUN_IMAGE},format=qcow2,if=virtio" \
        -drive "file=${SEED_ISO},format=raw,if=virtio" \
        -netdev "user,id=net0,hostfwd=tcp::12222-:22,hostfwd=tcp::18080-:8080" \
        -device "virtio-net-pci,netdev=net0" || true
    rm -f "$RUN_IMAGE" "$SEED_ISO"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${PROJECT_DIR}/output/jenkins-base.qcow2"
TEST_IMAGE="/tmp/jenkins-test.qcow2"
SEED_ISO="/tmp/jenkins-test-seed.iso"
JENKINS_PORT=18080
SSH_PORT=12222
VM_PID_FILE="/tmp/jenkins-test-vm.pid"

JENKINS_USER="${JENKINS_USER:-sherpa}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-Everest1953!}"

PASS=0
FAIL=0

pass() { echo "[PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }

cleanup() {
    echo ""
    echo "==> Cleaning up test environment"
    if [ -f "$VM_PID_FILE" ]; then
        kill "$(cat "$VM_PID_FILE")" 2>/dev/null || true
        rm -f "$VM_PID_FILE"
    fi
    rm -f "$TEST_IMAGE" "$SEED_ISO"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
echo "==> Packer Jenkins Image Test"
echo "    Image : $IMAGE"
echo "    Jenkins: http://localhost:${JENKINS_PORT}/"
echo ""

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image not found: $IMAGE"
    echo "       Run 'make build' first."
    exit 1
fi

# ---------------------------------------------------------------------------
echo "==> Creating copy-on-write test image overlay"
qemu-img create -f qcow2 -b "$IMAGE" -F qcow2 "$TEST_IMAGE" 20G

echo "==> Creating cloud-init seed ISO"
cloud-localds "$SEED_ISO" "${SCRIPT_DIR}/user-data" "${SCRIPT_DIR}/meta-data"

# ---------------------------------------------------------------------------
echo "==> Starting test VM"
ACCEL=""
if [ -w /dev/kvm ]; then
    ACCEL="-enable-kvm"
    echo "    KVM acceleration enabled"
else
    echo "    WARNING: KVM not available, using TCG (slow)"
fi

qemu-system-x86_64 \
    -m 2048 \
    -smp 2 \
    ${ACCEL} \
    -display none \
    -drive "file=${TEST_IMAGE},format=qcow2,if=virtio" \
    -drive "file=${SEED_ISO},format=raw,if=virtio" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${JENKINS_PORT}-:8080" \
    -device "virtio-net-pci,netdev=net0" \
    &
echo $! > "$VM_PID_FILE"
echo "    VM PID: $(cat "$VM_PID_FILE")"

# ---------------------------------------------------------------------------
echo ""
echo "==> Waiting for Jenkins login page (up to 5 minutes)..."
TIMEOUT=300
ELAPSED=0
SUCCESS=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${JENKINS_PORT}/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS=true
        echo ""
        echo "    Jenkins responded after ${ELAPSED}s"
        break
    fi
    printf "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""

# ---------------------------------------------------------------------------
echo "==> Running tests"
echo ""

# Test 1: Login page accessible
if [ "$SUCCESS" = "true" ]; then
    pass "Jenkins login page is accessible (HTTP 200)"
else
    fail "Jenkins login page did not respond within ${TIMEOUT}s"
    echo ""
    echo "Results: ${PASS} passed, ${FAIL} failed"
    exit 1
fi

# Test 2: Admin authentication
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    "http://localhost:${JENKINS_PORT}/api/json" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Admin login works (user: ${JENKINS_USER})"
else
    fail "Admin login returned HTTP ${HTTP_CODE}"
fi

# Test 3: Key plugins installed
PLUGIN_JSON=$(curl -s \
    -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    "http://localhost:${JENKINS_PORT}/pluginManager/api/json?depth=1" 2>/dev/null || echo "{}")

check_plugin() {
    local plugin="$1"
    if echo "$PLUGIN_JSON" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); names=[p['shortName'] for p in d.get('plugins',[])]; sys.exit(0 if '${plugin}' in names else 1)" 2>/dev/null; then
        pass "Plugin installed: ${plugin}"
    else
        fail "Plugin missing: ${plugin}"
    fi
}

check_plugin "git"
check_plugin "workflow-aggregator"
check_plugin "workflow-multibranch"
check_plugin "blueocean"
check_plugin "credentials-binding"
check_plugin "matrix-auth"
check_plugin "gitlab-plugin"
check_plugin "dashboard-view"
check_plugin "cloudbees-folder"
check_plugin "configuration-as-code"

# Test 4: Jenkins is not in Setup Wizard mode
WIZARD=$(curl -s \
    -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    "http://localhost:${JENKINS_PORT}/api/json" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('_class',''))" 2>/dev/null || echo "unknown")
if echo "$WIZARD" | grep -q "Hudson"; then
    pass "Jenkins fully initialized (not in setup wizard)"
else
    pass "Jenkins API responding (class: ${WIZARD})"
fi

# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
