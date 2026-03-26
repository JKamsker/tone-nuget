[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CursorPath,
    [string]$ReleaseTag,
    [switch]$Force,
    [switch]$DetectOnly,
    [switch]$SkipPush
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

$upstreamRepo = "sandreas/tone"
$upstreamRepoUrl = "https://github.com/$upstreamRepo"
$upstreamGitUrl = "$upstreamRepoUrl.git"
$packageId = "tone"
$packageDescription = "Cross-platform audio tagger and metadata editor for mp3, m4b, flac, and more."
$packageReadmeFile = "README.md"
$nugetSource = "https://api.nuget.org/v3/index.json"
$programVersionPlaceholder = "@package_version@"

function Write-Step {
    param([string]$Message)

    Write-Host "==> $Message"
}

function Set-WorkflowOutput {
    param(
        [string]$Name,
        [string]$Value
    )

    if (-not $env:GITHUB_OUTPUT) {
        return
    }

    Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value"
}

function Invoke-GitHubApi {
    param([string]$Uri)

    $headers = @{
        Accept     = "application/vnd.github+json"
        "User-Agent" = "tone-nuget-publisher"
    }

    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }

    Invoke-RestMethod -Headers $headers -Uri $Uri
}

function Get-UpstreamRelease {
    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        return Invoke-GitHubApi -Uri "https://api.github.com/repos/$upstreamRepo/releases/latest"
    }

    $encodedTag = [System.Uri]::EscapeDataString($ReleaseTag)
    return Invoke-GitHubApi -Uri "https://api.github.com/repos/$upstreamRepo/releases/tags/$encodedTag"
}

function Get-PackageVersion {
    param([string]$Tag)

    $version = $Tag.Trim()

    if ($version.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $version = $version.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not derive a package version from release tag '$Tag'."
    }

    return $version
}

function Get-Cursor {
    if (-not (Test-Path -LiteralPath $CursorPath)) {
        return [ordered]@{
            upstreamRepo      = $upstreamRepo
            lastPublishedTag  = $null
            packageVersion    = $null
            releasePublishedAt = $null
            releaseUrl        = $null
            updatedAtUtc      = $null
        }
    }

    return Get-Content -LiteralPath $CursorPath -Raw | ConvertFrom-Json -AsHashtable
}

function Write-Cursor {
    param(
        [hashtable]$Cursor,
        [string]$PackageVersion,
        $Release
    )

    $updatedAt = $Cursor.updatedAtUtc
    if ($Cursor.lastPublishedTag -ne $Release.tag_name -or $Cursor.packageVersion -ne $PackageVersion) {
        $updatedAt = (Get-Date).ToUniversalTime().ToString("O")
    }

    $newCursor = [ordered]@{
        upstreamRepo      = $upstreamRepo
        lastPublishedTag  = $Release.tag_name
        packageVersion    = $PackageVersion
        releasePublishedAt = $Release.published_at
        releaseUrl        = $Release.html_url
        updatedAtUtc      = $updatedAt
    }

    $existingJson = if (Test-Path -LiteralPath $CursorPath) {
        (Get-Content -LiteralPath $CursorPath -Raw).Trim()
    }
    else {
        ""
    }

    $newJson = $newCursor | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $CursorPath -Value $newJson

    return ($existingJson -ne $newJson.Trim())
}

function Write-DirectoryBuildProps {
    param(
        [string]$SourceRoot,
        [string]$PackageVersion
    )

    $propsPath = Join-Path $SourceRoot "Directory.Build.props"
    $props = @"
<Project>
  <PropertyGroup Condition="'`$(MSBuildProjectName)' == 'tone'">
    <LangVersion>12.0</LangVersion>
    <Version>$PackageVersion</Version>
    <PackageId>$packageId</PackageId>
    <Title>$packageId</Title>
    <Description>$packageDescription</Description>
    <Authors>sandreas</Authors>
    <PackageTags>audio;metadata;tagger;cli;dotnet-tool;m4b;mp3;flac</PackageTags>
    <PackageLicenseExpression>Apache-2.0</PackageLicenseExpression>
    <PackageProjectUrl>$upstreamRepoUrl</PackageProjectUrl>
    <RepositoryUrl>$upstreamRepoUrl</RepositoryUrl>
    <RepositoryType>git</RepositoryType>
    <PublishRepositoryUrl>true</PublishRepositoryUrl>
    <PackageReadmeFile>$packageReadmeFile</PackageReadmeFile>
    <IsPackable>true</IsPackable>
    <PackAsTool>true</PackAsTool>
    <ToolCommandName>tone</ToolCommandName>
  </PropertyGroup>
  <ItemGroup Condition="'`$(MSBuildProjectName)' == 'tone'">
    <None Include="`$(MSBuildThisFileDirectory)$packageReadmeFile" Pack="true" PackagePath="/" Condition="Exists('`$(MSBuildThisFileDirectory)$packageReadmeFile')" />
  </ItemGroup>
</Project>
"@

    Set-Content -LiteralPath $propsPath -Value $props
}

function Prepare-PackageReadme {
    param([string]$SourceRoot)

    $readmePath = Join-Path $SourceRoot $packageReadmeFile
    if (-not (Test-Path -LiteralPath $readmePath)) {
        throw "Expected upstream README at '$readmePath'."
    }

    $readmeContent = [System.IO.File]::ReadAllText($readmePath)
    if ([string]::IsNullOrWhiteSpace($readmeContent)) {
        throw "Upstream README is empty."
    }

    $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($readmePath, $readmeContent, $utf8WithBom)

    return $readmeContent
}

function Assert-PackageContainsReadme {
    param(
        [string]$PackagePath,
        [string]$ExpectedReadmeContent
    )

    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)

    try {
        $readmeEntry = $archive.Entries | Where-Object { $_.FullName -eq $packageReadmeFile } | Select-Object -First 1
        if (-not $readmeEntry) {
            throw "Package '$PackagePath' does not contain '$packageReadmeFile'."
        }

        $stream = $readmeEntry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream, $utf8Strict, $true)
            try {
                $packagedReadmeContent = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        if ($packagedReadmeContent -ne $ExpectedReadmeContent) {
            throw "Packaged README content does not match the upstream README content."
        }

        $nuspecEntry = $archive.Entries | Where-Object { $_.FullName -like "*.nuspec" } | Select-Object -First 1
        if (-not $nuspecEntry) {
            throw "Package '$PackagePath' does not contain a nuspec entry."
        }

        $nuspecStream = $nuspecEntry.Open()
        try {
            $nuspecReader = [System.IO.StreamReader]::new($nuspecStream, $utf8Strict, $true)
            try {
                $nuspecContent = $nuspecReader.ReadToEnd()
            }
            finally {
                $nuspecReader.Dispose()
            }
        }
        finally {
            $nuspecStream.Dispose()
        }

        $escapedReadmeFile = [System.Text.RegularExpressions.Regex]::Escape($packageReadmeFile)
        if ($nuspecContent -notmatch "<readme>$escapedReadmeFile</readme>") {
            throw "Package nuspec does not reference '$packageReadmeFile' as the package readme."
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Update-ProgramVersion {
    param(
        [string]$SourceRoot,
        [string]$PackageVersion
    )

    $programPath = Join-Path $SourceRoot "tone/Program.cs"
    $content = Get-Content -LiteralPath $programPath -Raw

    if (-not $content.Contains($programVersionPlaceholder)) {
        Write-Step "Program.cs no longer contains the version placeholder. Skipping source patch."
        return
    }

    $updated = $content.Replace($programVersionPlaceholder, $PackageVersion)
    Set-Content -LiteralPath $programPath -Value $updated
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

Set-WorkflowOutput -Name "cursor_updated" -Value "false"

$cursor = Get-Cursor
$release = Get-UpstreamRelease
$packageVersion = Get-PackageVersion -Tag $release.tag_name
$shouldPublish = $Force.IsPresent -or $cursor.lastPublishedTag -ne $release.tag_name

Write-Step "Upstream release: $($release.tag_name)"
Write-Step "Package version: $packageVersion"
Write-Step "Cursor release: $($cursor.lastPublishedTag)"

Set-WorkflowOutput -Name "upstream_tag" -Value $release.tag_name
Set-WorkflowOutput -Name "package_version" -Value $packageVersion
Set-WorkflowOutput -Name "should_publish" -Value $shouldPublish.ToString().ToLowerInvariant()

if (-not $shouldPublish) {
    Write-Step "No unpublished upstream release detected."
    return
}

if ($DetectOnly) {
    Write-Step "Detection only. Skipping build and publish."
    return
}

if (-not $SkipPush.IsPresent -and [string]::IsNullOrWhiteSpace($env:NUGET_API_KEY)) {
    throw "NUGET_API_KEY is not set."
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tone-nuget-" + [System.Guid]::NewGuid().ToString("N"))
$sourceRoot = Join-Path $tempRoot "source"
$packageOutput = Join-Path $tempRoot "nuget"

New-Item -ItemType Directory -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Path $packageOutput | Out-Null

try {
    Write-Step "Cloning upstream release $($release.tag_name)"
    Invoke-ExternalCommand -FilePath "git" -Arguments @(
        "-c", "core.autocrlf=false",
        "clone",
        "--depth", "1",
        "--branch", $release.tag_name,
        "--single-branch",
        $upstreamGitUrl,
        $sourceRoot
    ) -WorkingDirectory $tempRoot

    Write-Step "Injecting NuGet tool packaging metadata"
    Write-DirectoryBuildProps -SourceRoot $sourceRoot -PackageVersion $packageVersion
    Update-ProgramVersion -SourceRoot $sourceRoot -PackageVersion $packageVersion
    $expectedReadmeContent = Prepare-PackageReadme -SourceRoot $sourceRoot

    Write-Step "Running upstream tests"
    Invoke-ExternalCommand -FilePath "dotnet" -Arguments @(
        "test",
        "tone.Tests/tone.Tests.csproj",
        "--configuration", "Release",
        "/p:Version=$packageVersion",
        "/p:LangVersion=12.0"
    ) -WorkingDirectory $sourceRoot

    Write-Step "Packing NuGet tool"
    Invoke-ExternalCommand -FilePath "dotnet" -Arguments @(
        "pack",
        "tone/tone.csproj",
        "--configuration", "Release",
        "--output", $packageOutput,
        "--no-restore",
        "/p:Version=$packageVersion",
        "/p:LangVersion=12.0"
    ) -WorkingDirectory $sourceRoot

    $packagePath = Join-Path $packageOutput "$packageId.$packageVersion.nupkg"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Expected package '$packagePath' was not created."
    }

    Write-Step "Validating packaged upstream README"
    Assert-PackageContainsReadme -PackagePath $packagePath -ExpectedReadmeContent $expectedReadmeContent

    if ($SkipPush.IsPresent) {
        Write-Step "SkipPush enabled. Leaving package at $packagePath"
        return
    }

    Write-Step "Pushing package to nuget.org"
    Invoke-ExternalCommand -FilePath "dotnet" -Arguments @(
        "nuget",
        "push",
        $packagePath,
        "--api-key", $env:NUGET_API_KEY,
        "--source", $nugetSource,
        "--skip-duplicate"
    ) -WorkingDirectory $sourceRoot

    Write-Step "Updating cursor file"
    $cursorUpdated = Write-Cursor -Cursor $cursor -PackageVersion $packageVersion -Release $release
    Set-WorkflowOutput -Name "cursor_updated" -Value $cursorUpdated.ToString().ToLowerInvariant()
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
