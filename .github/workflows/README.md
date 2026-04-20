# Diyar OS — GitHub Actions Workflows

## Workflows

| Workflow | File | Trigger | Duration |
|---|---|---|---|
| **Build ISO** | `build-iso.yml` | push to main/develop, manual, weekly | ~60 min |
| **Validate** | `validate.yml` | every push & PR | ~2 min |
| **Check Deps** | `check-deps.yml` | weekly Monday | ~5 min |

---

## Build ISO — detailed flow

```
push/tag/manual
      │
      ▼
 ┌─────────────┐
 │  validate   │  ← syntax check, XML, package lists (2 min)
 └──────┬──────┘
        │ passes
        ▼
 ┌─────────────┐
 │    build    │  ← lb config → lb build → ISO (60 min)
 └──────┬──────┘
        │ success
        ▼
 ┌─────────────┐
 │ smoke-test  │  ← QEMU headless boot check (5 min)
 └──────┬──────┘
        │ (on manual release=true OR version tag)
        ▼
 ┌─────────────┐
 │   release   │  ← GitHub Release with ISO + checksum
 └─────────────┘
```

## Triggering a release

### Method 1 — Version tag (recommended)
```bash
git tag v1.0.0
git push origin v1.0.0
# → triggers build → smoke-test → GitHub Release automatically
```

### Method 2 — Manual dispatch
1. Go to **Actions** → **Build Diyar OS ISO**
2. Click **Run workflow**
3. Set version (e.g. `1.0.0`) and check **Create GitHub Release**
4. Click **Run workflow**

## Artifacts

Every successful build uploads:
- `diyar-os-iso-<version>` — the ISO + SHA256 (retained 30 days)
- `build-log-<version>` — full lb build log (retained 14 days)
- `qemu-boot-log-<version>` — QEMU boot output (retained 7 days)

## Required secrets

No extra secrets needed. The workflow uses `GITHUB_TOKEN` (automatically provided) for creating releases.

## Disk space

The GitHub Actions `ubuntu-latest` runner has ~14 GB free by default. The build step removes unused tools to free ~8 GB more, giving ~22 GB total — enough for the ISO build (~8-10 GB working space + ~2-3 GB output ISO).

## Debugging a failed build

1. Enable **debug_enabled** in manual dispatch
2. A tmate session opens — connect via the URL printed in the log
3. You have 30 minutes to inspect the runner

Or download the `build-log-<version>` artifact and search for the first `E:` (apt error) or the hook that failed.
