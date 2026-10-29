# Shared account availability

AccountKit, Pix and Kaji share `~/.pix/accounts.json`. An account may have:

```json
{"id":"own","label":"brook","disabled":true,"disabledReason":"oauth_org_denied","disabledAt":1793258556357}
```

These are optional metadata fields, not credentials. Missing or false `disabled` means the original behavior. `disabledAt` is the operator-action timestamp, not proof of a successful request.

Kaji keeps disabled accounts visible, shows `unavailable, organization denied` (or `disabled` for another reason), hides stale quota values and Use, and excludes them from active-account selection. A preserved disabled route is not an active account. Both the popover and its selection handler reject unavailable accounts. Re-reading the inventory overrides an older quota snapshot, including after re-enable.

The collector skips disabled accounts' quota requests, including the default Claude login's top-level request, while preserving credential-presence metadata. Disabled is not signed out. Codex inventory and ordinary enabled-account behavior are unchanged.

## Migration and rollback

Use AccountKit's CLI from its Pix checkout:

```sh
node /path/to/pix/packages/accountkit/cli.ts disable own oauth_org_denied
node /path/to/pix/packages/accountkit/cli.ts disable minarabench oauth_org_denied
# After organization access is restored:
node /path/to/pix/packages/accountkit/cli.ts enable own
node /path/to/pix/packages/accountkit/cli.ts enable minarabench
```

Back up inventory privately first. No credentials, route pins, usage history or sessions need migration. Re-enable removes only availability fields and preserves unrelated/newer account configuration. Never delete a login to represent organization denial.

Deploy the updated Kaji and Pix consumers through their normal release paths. Merely writing metadata does not update an already-running old app or the deployed phone Worker.

## Checks

- `swift build` and `swift test` (cached quota, preserved pins, forged selection, re-enable and native rendering).
- `python3 Tests/quota/test_quota.py` (disabled inventory stays visible and makes no quota requests).
- Native render evidence: `.build/ui-snapshots/popover-accounts-disabled.png`.
