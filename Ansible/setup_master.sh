#!/usr/bin/env bash
#
# Ansible master bootstrap script.
#
# Terraform copies this script (and every other file it needs) onto the
# master server and runs it automatically during `terraform apply`.
# When it finishes you can SSH straight in and run the playbook:
#
#     ssh -i ~/.ssh/id_rsa ubuntu@<master-public-ip>
#     cd ~/ansible
#     ansible-playbook playbook.yml
#
set -euo pipefail

# pip installs binaries into ~/.local/bin - expose them in this shell
export PATH="${HOME}/.local/bin:${PATH}"

ANSIBLE_DIR="${HOME}/ansible"

echo "==> Updating the package index..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y

echo "==> Installing prerequisites (python3-pip, openssh-client)..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip openssh-client

echo "==> Installing Ansible with pip..."
pip3 install --user --upgrade ansible

echo "==> Securing the SSH key used to reach the worker..."
chmod 600 "${HOME}/.ssh/id_rsa"

echo "==> Ensuring the community.docker collection is available..."
if ! ansible-doc community.docker.docker_container >/dev/null 2>&1; then
  ansible-galaxy collection install community.docker
fi

echo "==> Files seeded into ${ANSIBLE_DIR}:"
ls -la "${ANSIBLE_DIR}"
echo "==> Inventory:"
cat "${ANSIBLE_DIR}/inventory/hosts"

echo "==> Ansible version:"
ansible --version | head -n 1

echo "==> Checking connectivity to the worker..."
cd "${ANSIBLE_DIR}"
worker_reachable=false
for attempt in $(seq 1 10); do
  if ansible all -m ping; then
    worker_reachable=true
    echo "==> Worker is reachable."
    break
  fi
  echo "    attempt ${attempt}/10 failed, retrying in 10s..."
  sleep 10
done

if [ "${worker_reachable}" != "true" ]; then
  echo "WARNING: the master could not reach the worker yet."
  echo "         Check ${ANSIBLE_DIR}/inventory/hosts before running the playbook."
fi

cat <<'EOF'

============================================================
  Ansible master is ready.

  SSH in and run the playbook:

      ssh -i ~/.ssh/id_rsa ubuntu@<master-public-ip>
      cd ~/ansible
      ansible-playbook playbook.yml

  The playbook installs and starts Docker on the worker and
  runs an Nginx container on port 80.
============================================================
EOF
