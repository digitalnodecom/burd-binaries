# burd-binaries

Portable, self-contained macOS service binaries for [Burd](https://github.com/digitalnodecom/burd), published to GitHub Releases with checksums.

Burd needs standalone versions of databases, caches, and other services that don't require Homebrew and run from any location. This repo builds them in CI and hosts them, so the main app never bundles or commits large binaries and always has current, integrity-verified builds to download.

## What's here

Two pipelines, both publishing the same portable package layout (`bin/`, `lib/`, `etc/`, `manifest.json`) to per-service GitHub Releases with checksums.

**Bottle-extracted services** — extracted from Homebrew bottles and relinked to `@executable_path` (Herd-style portability), so they carry their own dylibs and run standalone:

`mariadb`, `mysql`, `postgresql`, `redis`, `valkey`, `memcached`, `beanstalkd`

Each is defined by a `formulas/<name>.json` describing its binaries, dylib dependencies, and a functional test.

**Mirrored services** — prebuilt, already-portable upstream binaries repackaged into the same layout:

`frpc` (from `fatedier/frp`), `mailpit` (from `axllent/mailpit`)

Each is defined by a `mirrors/<name>.json` naming the upstream repo, per-arch asset, and which binaries to keep.

**Custom FrankenPHP** — self-contained static PHP application-server binaries built with the full extension set Burd needs (`redis`, `mongodb`, `imagick`, `memcached`, `intl`, and many more) that the official FrankenPHP builds omit. Built for PHP **8.3, 8.4, and 8.5**.

Each PHP line's extension list lives in `frankenphp/configs/build-<php>.env`.

## How it works

Bottles (macOS runners, needs `brew`):

```
brew fetch --bottle-tag   →  extract  →  relink to @executable_path
  →  bundle dylibs  →  verify (paths + functional test)  →  package + sha256
  →  publish to a per-formula GitHub Release
```

Mirrors (Linux runners — just repackaging):

```
download upstream release asset  →  extract wanted binaries
  →  repackage to bin/  →  manifest + sha256  →  publish to a GitHub Release
```

FrankenPHP (macOS runners, static build — ~45-60 min each):

```
clone dunglas/frankenphp  →  build-static.sh with the extension set
  →  test (version + php-cli -m)  →  publish binary + sha256 to a release
```

- `extract.sh` / `lib/*` — bottle extraction toolkit (macOS + `brew`)
- `mirror.sh` / `mirrors/*` — upstream repackaging
- `frankenphp/` — FrankenPHP build configs + scripts
- `.github/workflows/build-bottles.yml` — builds every formula for `arm64` + `x86_64`
- `.github/workflows/build-mirrors.yml` — builds every mirror for `arm64` + `x86_64`
- `.github/workflows/build-frankenphp.yml` — builds each PHP line for `arm64` + `x86_64` (manual / monthly, not on push)

## Releases

One release per formula version, tagged `<formula>-<version>` (e.g. `redis-8.8.0`), with assets:

```
<formula>-<version>-arm64.tar.gz      + .sha256
<formula>-<version>-x86_64.tar.gz     + .sha256
```

Each archive unpacks to `bin/`, `lib/`, `etc/`, and a `manifest.json` (per-binary checksums).

## Building

Automatic:
- **Weekly schedule** picks up new upstream bottle versions.
- **Push** to `formulas/`, `lib/`, or `extract.sh` rebuilds affected binaries.

Manual: run the **Build bottle binaries** workflow (`workflow_dispatch`), optionally naming a single formula.

Locally (macOS + Homebrew):

```bash
./extract.sh redis                 # latest, host arch
./extract.sh mariadb 11.4.2 arm64  # specific version/arch
```

## Adding a service

1. Add `formulas/<name>.json` (copy an existing one; list its binaries + dylib deps).
2. Run `./extract.sh <name>` locally to verify it extracts and passes the functional test.
3. Push — CI builds and publishes it.

## License

The build tooling in this repo is MIT-licensed. Each published binary retains its
upstream project's own license (see the bundled `LICENSE`/`README` in each archive).
