# atlassian

Tooling for Atlassian (Jira/Confluence/Bitbucket) administration.

## inactive-license-audit.py

Finds Active human users inactive for N+ days from a managed-accounts CSV
export, so unused seats can be reclaimed — while separating out service/bot
accounts so they're never mistakenly deprovisioned.

```bash
./inactive-license-audit.py accounts.csv \
    --out inactive.csv --bots-out excluded_bots.csv \
    --cutoff-days 60 --as-of 2026-04-07 --bots-file known_bots.txt
```

Bot detection is heuristic (email/name patterns). Site-specific service-account
names go in `--bots-file` (gitignored), **not** in source — keep real account
names out of the repo.
