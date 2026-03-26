# Publishing Automation

## Purpose

This repository watches [sandreas/tone](https://github.com/sandreas/tone) for new GitHub releases and publishes the `tone` .NET tool package to nuget.org when a new upstream release appears.

## Triggering

- The workflow runs daily at `20:00 UTC`.
- The workflow can also be started manually with `workflow_dispatch`.

## Workflow

- The workflow definition lives in [publish.yml](../.github/workflows/publish.yml).
- It checks the latest upstream release or a manually supplied tag.
- It compares that release with [published-release.json](../state/published-release.json).
- If the upstream tag is already recorded, the run exits cleanly without publishing.
- If the upstream tag is new, the script clones the upstream release tag, injects NuGet packaging metadata, runs tests, packs the tool, pushes it to nuget.org, and updates the cursor file.

## Script

- The publishing logic lives in [publish-tone-release.ps1](../scripts/publish-tone-release.ps1).
- The NuGet package version is derived from the upstream release tag by removing the leading `v`.
- The package id and tool command name are both `tone`.

## State

- [published-release.json](../state/published-release.json) is the cursor file.
- It records the last upstream tag that was successfully published, the package version, and the upstream release metadata.
- After a successful publish, the workflow commits the updated cursor file back to the `main` branch.

## Secrets

- The repository requires the `BW_ACCESS_TOKEN` GitHub secret.
- The workflow uses Bitwarden Secrets Manager and maps secret `265b2fb6-2cf0-4859-9bc8-b24c00ab4378` to `NUGET_API_KEY`.
- If `BW_ACCESS_TOKEN` is not configured, the workflow skips the publish path instead of failing scheduled runs.

