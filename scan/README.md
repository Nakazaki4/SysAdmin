# scan — lab network security assessment

This repository contains the Vagrant/IaC environment for a three-VM lab
hosting OWASP Juice Shop behind a gateway, together with a security
assessment of that environment.

Primary deliverable: **[report/assessment.md](report/assessment.md)**.

## Layout

```
.
├── README.md            # this file
├── Vagrantfile          # topology + provisioners
├── provision/           # shell provisioners, including the IaC remediations
├── report/
│   └── assessment.md    # the security assessment report
├── scans/
│   ├── run-scans.sh     # runs the full baseline scan from clientA
│   ├── before/          # scan evidence before remediation
│   └── after/           # scan evidence after `vagrant destroy && up`
└── remediation/
    └── notes.md         # per-finding commit mapping
```

## Reproducing the assessment

```bash
vagrant up                   # bring up gateway, clientA, clientB
bash scans/run-scans.sh before   # or 'after' when validating fixes
```

The scan script SSHes into clientA via the gateway as a bastion and runs
`arp-scan`, `nmap`, and `curl` in the sequence described in the methodology
section of the report. Each probe writes to its own file so the before/after
pairs can be diffed directly.

## Accepted risks

The private SSH key `remote_machines_ed25519` is intentionally committed to
make the lab reproducible. Anyone with repo access can log in to any VM in
the lab. Do not take this layout as a model for production.
