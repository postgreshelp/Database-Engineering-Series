# Quick Start — 3 Commands

```bash
# 1. Configure your email
sed -i 's/your-email@gmail.com/YOUR_EMAIL@gmail.com/g' monitoring.sh
sed -i 's/YOUR_16_CHAR_APP_PASSWORD/YOUR_APP_PASSWORD/g' monitoring.sh

# 2. Deploy
sh monitoring.sh

# 3. Open Grafana
# http://YOUR_IP:3000  (admin/admin)
```

That's it. Full PostgreSQL observability in under 5 minutes.

## Test it works
```bash
# Fire an alert
systemctl stop postgresql-18

# Watch :9090/alerts → pending → firing
# Check your Gmail inbox

# Recover
systemctl start postgresql-18
```

## Reset everything
```bash
sh cleanup.sh
```
