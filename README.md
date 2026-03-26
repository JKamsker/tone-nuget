# tone-nuget

[![Build](https://github.com/JKamsker/tone-nuget/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/JKamsker/tone-nuget/actions/workflows/publish.yml)
[![Forks](https://img.shields.io/github/forks/sandreas/tone?style=flat-square)](https://github.com/sandreas/tone/network/members)
[![Stars](https://img.shields.io/github/stars/sandreas/tone?style=flat-square)](https://github.com/sandreas/tone/stargazers)
[![NuGet](https://img.shields.io/nuget/v/tone?style=flat-square)](https://www.nuget.org/packages/tone)

This repository exists to publish the `tone` .NET tool to NuGet when the upstream project ships a new release.

The original project lives at [sandreas/tone](https://github.com/sandreas/tone).

## Install

```bash
dotnet tool install --global tone
```

If you landed here looking for the actual application source, use the upstream repository above. This repo only contains the automation that watches upstream releases and republishes the CLI package.

Implementation details, workflow behavior, and operational notes are documented in [docs/publishing.md](./docs/publishing.md).
