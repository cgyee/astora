# Grafana Alloy Log Collection Design

## Overview

Configure Grafana Alloy servers to collect systemd journal logs and forward them to a central Loki instance at `leader.lab.local:3100`.

## Architecture

**Components:**
- **Source:** `loki.source.journal` - reads from systemd journal on each Alloy server
- **Destination:** `loki.write` - pushes to Loki via HTTP API

**Data flow:**
```
Alloy Server → journal → loki.source.journal → loki.write → leader.lab.local:3100 (Loki)
```

**Deduplication:** Position tracking via `/var/lib/alloy/positions/journal.pos` ensures logs aren't resent after restarts.

**Labels attached to each log:**
- `hostname` - identifies the source server
- `job="systemd-journal"` - identifies log type
- `unit` - systemd service name (e.g., `sshd.service`, `nginx.service`)
- `priority` - log level (0=emerg through 7=debug)

## Alloy Configuration

Config file: `/etc/alloy/config.alloy`

```hcl
// Read from systemd journal
loki.source.journal "systemd" {
  forward_to    = [loki.write.default.receiver]
  relabel_rules = loki.relabel.journal.rules
  path          = "/var/lib/alloy/positions/journal.pos"
}

// Extract and normalize labels
loki.relabel "journal" {
  rule {
    source_labels = ["__journal__hostname"]
    target_label  = "hostname"
  }
  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
  rule {
    source_labels = ["__journal_priority_keyword"]
    target_label  = "priority"
  }
}

// Send to Loki
loki.write "default" {
  endpoint {
    url = "http://leader.lab.local:3100/loki/api/v1/push"
  }
}
```

## Ansible Structure

```
ansible/
├── inventory/
│   └── hosts.yml           # Define alloy_servers group
├── roles/
│   └── alloy_config/
│       ├── tasks/
│       │   └── main.yml    # Deploy config, restart service
│       ├── templates/
│       │   └── config.alloy.j2   # Templated Alloy config
│       └── handlers/
│           └── main.yml    # Restart handler
└── playbooks/
    └── configure-alloy.yml # Main playbook
```

**Playbook logic:**
1. Ensure `/var/lib/alloy/positions` directory exists
2. Deploy templated config to `/etc/alloy/config.alloy`
3. Restart `alloy.service` only when config changes (handler)

**Variables:**
- `loki_endpoint: "http://leader.lab.local:3100/loki/api/v1/push"`

## Usage

**Running the playbook:**
```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/configure-alloy.yml
```

**Inventory example (`inventory/hosts.yml`):**
```yaml
all:
  children:
    alloy_servers:
      hosts:
        server1.lab.local:
        server2.lab.local:
```

## Verification

1. SSH to an Alloy server and check service: `systemctl status alloy`
2. Check Alloy logs for errors: `journalctl -u alloy -f`
3. Query Loki to confirm logs arriving:
   ```bash
   curl -G 'http://leader.lab.local:3100/loki/api/v1/query' \
     --data-urlencode 'query={job="systemd-journal"}'
   ```
