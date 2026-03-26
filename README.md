# tone-nuget

This repository exists to publish the `tone` .NET tool to NuGet when the upstream project ships a new release.

The original project lives at [sandreas/tone](https://github.com/sandreas/tone).

If you landed here looking for the actual application source, use the upstream repository above. This repo only contains the automation that watches upstream releases and republishes the CLI package.

Implementation details, workflow behavior, and operational notes are documented in [docs/publishing.md](./docs/publishing.md).

