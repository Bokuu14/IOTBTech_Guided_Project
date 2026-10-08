# AWS Infra with Terraform + Ansible

Two Ubuntu boxes on AWS: one runs Ansible, the other gets configured by it.
Terraform builds the whole network + both servers, then reaches into the
master over SSH, drops the Ansible project on it and installs Ansible, so
the moment `terraform apply` finishes you can log in and run the playbook.

```
Your laptop ──terraform apply──▶ AWS (eu-west-1)
                                   │
                                   ├─ master  (ansible-master)      t3.micro
                                   │    └─ ssh's into ▼
                                   └─ worker  (ansible-worker-node) t3.micro
                                        └─ Docker + Nginx on port 80
```

## The layout

```
Ansible/
  playbook.yml      # installs Docker on the worker, runs the Nginx container
  ansible.cfg       # points at the inventory, sets ubuntu + the key
  setup_master.sh   # installs Ansible on the master, sanity-checks the worker

Terraform/
  main.tf           # VPC, subnet, IGW, routes, SG, key pair, both instances,
                    # and the terraform_data block that seeds the master
  variables.tf
  terraform.tfvars  # region, key name, CIDRs
  outputs.tf        # master_public_ip, worker_public_ip
```

## How it actually works

1. `terraform apply` builds the VPC and both instances (Ubuntu 22.04, t3.micro).
2. A `terraform_data` resource (`seed_master` in `main.tf`) SSHes into the
   master and:
   - creates `~/ansible`
   - copies `playbook.yml`, `ansible.cfg` and `setup_master.sh` into it
   - writes `inventory/hosts` with the worker's **private** IP (the two boxes
     sit in the same subnet, so no need to go out and back in through the
     public internet)
   - copies your private key onto the master so it can authenticate to the worker
   - runs `setup_master.sh`, which installs Ansible via pip, makes sure the
     `community.docker` collection is there, and pings the worker
3. You SSH in and run the playbook. That's it.

The seeding step re-runs on its own whenever the master or worker gets
replaced, or whenever you edit any of the three Ansible files locally —
Terraform hashes them in `triggers_replace`. If nothing changed, apply does
nothing to the master and stays fast.

## Prerequisites

- AWS credentials configured (`aws configure` or env vars)
- Terraform installed
- An SSH keypair at `~/.ssh/id_rsa` / `~/.ssh/id_rsa.pub` — Terraform reads
  the public key and registers it as `Dove-key` in AWS, and uses the private
  key for the provisioning SSH and for master → worker
- You do **not** need Ansible installed on your laptop. That's the whole
  point — it lives on the master.

## Running it

```bash
cd Terraform
terraform init
terraform apply
```

Watch the apply output — the tail end is the `setup_master.sh` script
running on the master, ending with a connectivity check against the worker.

Grab the IPs:

```bash
terraform output -raw master_public_ip
terraform output -raw worker_public_ip
```

SSH in and run the playbook:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<master_public_ip>
cd ~/ansible
ansible-playbook playbook.yml
```

Everything you need is already on the master:

```
~/ansible/
  playbook.yml
  ansible.cfg
  setup_master.sh
  inventory/hosts     # [workers] + the worker's private IP
~/.ssh/id_rsa         # same key, so ansible can reach the worker
```

The playbook does the following on the worker:

- installs `docker.io` and `python3-docker` (the SDK Ansible's docker
  modules need)
- enables and starts the Docker service
- adds the `ubuntu` user to the `docker` group
- pulls the Nginx image and runs it as `web-server` on port 80 with
  `restart: always`
- inspects the container and asserts it's actually running

Check it from your laptop once the playbook finishes:

```bash
curl http://$(terraform output -raw worker_public_ip)
```

You should get the default Nginx welcome page.

## Changing the playbook

Edit `Ansible/playbook.yml` locally, then:

```bash
cd Terraform
terraform apply
```

The `seed_master` resource notices the file hash changed, re-copies
everything to the master and re-runs the setup script. Then SSH in and run
the playbook again. (If you only changed the playbook and not the setup
script, the re-run of the setup script is quick — pip sees Ansible is
already installed.)

## Cleanup

```bash
cd Terraform
terraform destroy
```

Tears down both instances and the whole network. Nothing in AWS is left
paying for itself after that.

## Honest caveats

This is a lab setup, not something to point at production:

- The security group opens port 22 to `0.0.0.0/0`. Lock it down to your own
  IP before you leave this running anywhere real.
- Your private key sits on the master's disk. Fine for a demo; in real life
  you'd generate a separate keypair just for master → worker, or use SSM
  Session Manager and skip inbound SSH entirely.
- Both boxes get public IPs. A private subnet for the worker plus a NAT
  gateway would be the "proper" version of this.
