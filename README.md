# tone-nuget

Automation repo for publishing the `tone` .NET tool package from upstream `sandreas/tone` releases.

## How It Works

- Runs daily at `20:00 UTC` and on manual dispatch.
- Checks the latest GitHub release from `https://github.com/sandreas/tone`.
- Compares the upstream release tag with [`state/published-release.json`](./state/published-release.json).
- If the release is new, clones the upstream tag, adds NuGet tool packaging metadata, packs `tone`, pushes it to nuget.org, and commits the updated cursor file back to `main`.

## Required Secret

Set the repository secret `BW_ACCESS_TOKEN`.

The workflow uses Bitwarden Secrets Manager and maps secret `265b2fb6-2cf0-4859-9bc8-b24c00ab4378` to `NUGET_API_KEY`.

## Notes

- The NuGet package version mirrors the upstream GitHub release version without the leading `v`.
- The workflow skips publishing cleanly when no new upstream release exists.
- If `BW_ACCESS_TOKEN` is missing, the workflow exits without publishing instead of failing the scheduled run.

