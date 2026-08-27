# SwirlLMCloudBench.jl

## Overview

**Julia bindings** for:

- [Swirl-LM](https://github.com/google-research/swirl-lm)
- [CloudBench](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)
- [High- resolution simulations reveal positive global
warming feedback from Pacific low clouds (https://doi.org/10.1126/sciadv.aec8488)](https://doi.org/10.1126/sciadv.aec8488)

Use this package to build URLs, download `sounding.csv` / `parameters.json`, open **`data.zarr`** lazily over HTTPS (or from a local tree), and iterate CloudBench cases.

**Optional extensions** (loaded when the corresponding package is available):

- **ClimaAtmos** — drive a single-column ClimaAtmos run with forcing from a CloudBench sounding: `ClimaAtmosSwirlLMCloudBenchForcing` / `ClimaAtmosSwirlLMCloudBenchSetup`, plus `ClimaAtmos_SwirlLMCloudBench_params` for the matching ClimaParams overrides, composing ClimaAtmos's own GCM-driven (Shen et al. 2022) forcing kernels — the same methodology CloudBench was run with.
- **OhMyThreads** — `cloudbench_tmap` for threaded iteration over collections (e.g. many `CloudBenchSimulation` / `CloudBenchInstance` values).
- **Distributed** — `cloudbench_pmap_download_raw!` to download many simulations in parallel (`pmap` over `download_cloudbench_raw!`).

**Authors:** see `Project.toml` (`authors`).

---

## What this package provides

`SwirlLMCloudBench` offers **catalog** constants for the published CloudBench ensemble, **path and cache** helpers, and the **`Simulation`** submodule for public-bucket `sounding.csv` and `parameters.json`, lazy **`data.zarr`** via `SwirlLMCloudBench.Simulation.open_zarr`, optional sounding-based **grouped NetCDF** (same variable names as `sounding.csv`), **lazy selection** over `(site_id, month, experiment)`, and a **mutable download cache** under [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) (`Config.raw_download_root()` / `SWIRL_LM_CLOUDBENCH_RAW_ROOT`) mirroring `[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/`.

Condensed-phase **`q_c`** in CloudBench is described in the upstream README (with `q_r`, `q_s`, etc.); this package provides **`split_q_c`** (`SwirlLMCloudBench.Simulation.split_q_c`) using the Swirl-LM temperature ramp.

---

## Capabilities

| Area | What works today |
|------|------------------|
| Core (`Catalog`, `Paths`, `Config`, `Artifacts`) | Case indices, months, experiment names, default roots, artifact resolution. |
| **`Simulation`** | `CloudBenchInstance`, `CloudBenchSimulation` (metadata + output backend), URLs, `download_cloudbench_raw!`, Scratch/env-backed **`Config.raw_download_root()`**, **`open_zarr`** (HTTPS), **`open_zarr_local`** (path + instance, or a simulation with **`LocalCloudBenchMirrorOutput`**), sounding NetCDF helpers, **`split_q_c`**, **`CloudBenchSelection`**. Catalog keys and selection need no network. Mirroring the full Zarr store via `download_cloudbench_raw!(…; zarr=true)` is not supported yet — use **`open_zarr`** for remote lazy access. |
| **ClimaAtmos extension** | `ClimaAtmosSwirlLMCloudBenchForcing` / `ClimaAtmosSwirlLMCloudBenchSetup` (GCM-driven forcing + initial conditions), `write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!` / `read_ClimaAtmosSwirlLMCloudBenchForcing`, `ClimaAtmos_SwirlLMCloudBench_toml_overrides` / `ClimaAtmos_SwirlLMCloudBench_params`, `ClimaAtmosSwirlLMCloudBench_callback_kwargs`, `CloudBenchInsolation`, `climaatmos_pkg_version`. |
| **OhMyThreads extension** | `cloudbench_tmap`. |
| **Distributed extension** | `cloudbench_pmap_download_raw!` (parallel raw downloads). |

Example (ClimaAtmos extension):

```julia
using SwirlLMCloudBench: SwirlLMCloudBench, Simulation as S
using ClimaAtmos: ClimaAtmos   # activates the extension when versions are compatible
```

## Install

**Published clone** (package-only repo):

```julia
using Pkg
Pkg.add(url="https://github.com/jbphyswx/SwirlLMCloudBench.jl")
```

**Local monorepo checkout:**

```julia
using Pkg
Pkg.develop(path="/path/to/SwirlLMCloudBench/SwirlLMCloudBench.jl")
```

Or add a `path` dependency in your project’s `Project.toml`.

## Usage

The examples below assume:

```julia
using SwirlLMCloudBench: Catalog, Paths, Config, CaseDirs, Simulation as S
```

In the Julia REPL, `?S.CloudBenchSimulation`, `?S.CloudBenchInstance`, `?S.open_zarr`, etc. show the full docstrings (or use the fully qualified `SwirlLMCloudBench.Simulation.…` names).

### Pick a case

A run is identified by **`site_id`** (integer in `Catalog.CLOUDBENCH_CASE_INDICES`, i.e. `0:499`), **`month`** in `Catalog.CLOUDBENCH_MONTHS` (`1`, `4`, `7`, `10`), and **`experiment`**. Constructors accept a catalog `Symbol` or string (e.g. `"amip-p4k"`); **`CloudBenchInstance.experiment`** is stored as **`Catalog.CloudBenchExperiment`** (a `UInt8` enum, `isbitstype`).

- **`CloudBenchInstance`** — catalog key only (no loaded metadata, no output handle).
- **`CloudBenchSimulation`** — **`metadata`** (`CloudBenchMetadata{P,S}`: instance + **concrete** `parameters::P` and `sounding::S`, often `CloudBenchMetadataEmpty` or `CloudBenchMetadata{CloudBenchParameters,CloudBenchSounding}`) and **`output`** (`AbstractCloudBenchSimulation`: e.g. remote HTTPS Zarr vs local mirror `root`). Common type aliases: `CloudBenchSimulationRemote` (empty metadata), `CloudBenchSimulationLoaded` (parsed files + local mirror), `CloudBenchSimulationRemoteLoaded` (parsed files + remote Zarr only).

The usual default **`CloudBenchSimulation(0, 1, :amip)`** builds empty optional metadata and **`RemoteCloudBenchZarrOutput()`** (stream `data.zarr` over HTTPS; no local cache).

```julia
sim = S.CloudBenchSimulation(0, 1, :amip)   # lightweight: remote Zarr output
inst = S.CloudBenchInstance(0, 1, :amip)    # key only
Catalog.n_cases()                            # 500
Catalog.experiment_names()                   # all experiment symbols
```

### URLs (no download)

```julia
S.cloudbench_sounding_url(sim)
S.cloudbench_parameters_url(sim)
S.cloudbench_zarr_url(sim)
```

### Download `sounding.csv` and `parameters.json`

Files go under **`[root]/[site_id]/[month]/[experiment-segment]/`** (same layout as the public bucket).  
If you omit `root`, [`Config.raw_download_root()`](https://github.com/JuliaPackaging/Scratch.jl) (or `SWIRL_LM_CLOUDBENCH_RAW_ROOT`) is used.

```julia
dir = S.download_cloudbench_raw!(sim)           # both files, skip if present
csv = S.ensure_cloudbench_sounding_local!(sim)  # sounding only
```

`download_cloudbench_raw!` does **not** mirror the full `data.zarr` tree (`zarr` must stay `false`). For Zarr, use `open_zarr` below.

### Load parameters and sounding from disk

```julia
# After download, metadata + LocalCloudBenchMirrorOutput(root) (default):
loaded = S.load_cloudbench_simulation(S.CloudBenchInstance(0, 1, :amip); download=true)
loaded.metadata.parameters   # CloudBenchParameters
loaded.metadata.sounding     # CloudBenchSounding — full bucket schema (`Simulation.CLOUDBENCH_SOUNDING_CSV_HEADER`); expand to `(z,time)` with `Simulation.cloudbench_sounding_zt_matrices`
loaded.output.root           # local mirror root used for that tree

# Same metadata from disk, but keep RemoteCloudBenchZarrOutput (HTTPS Zarr; no LocalCloudBenchMirrorOutput):
remote_meta = S.load_cloudbench_simulation(S.CloudBenchInstance(0, 1, :amip); download=true, local_mirror=false)
remote_meta isa S.CloudBenchSimulationRemoteLoaded
S.open_zarr(remote_meta)   # lazy HTTPS Zarr

# Or from paths you already have:
s = S.load_cloudbench_sounding(S.sounding_path(sim, root))
```

### Open `data.zarr` (lazy, HTTPS)

Uses [Zarr.jl](https://github.com/JuliaIO/Zarr.jl); metadata loads immediately, array reads happen when you index.

```julia
zg = S.open_zarr(sim)
# Inspect and read variables using the CloudBench / Swirl-LM field list (e.g. q_c, T, …).
```

If you have a **local** directory `data.zarr` under the same bucket-shaped `root`, use `S.open_zarr_local(sim, root)` or `S.open_zarr_local(S.cloudbench_instance(sim), root)` (errors if the path is missing). If `sim.output isa S.LocalCloudBenchMirrorOutput`, you can call `S.open_zarr_local(sim)` with one argument.

### Split condensed water `q_c` into liquid and ice

CloudBench publishes a single `q_c`; this package splits it using the Swirl-LM temperature ramp (see `?S.split_q_c`).

```julia
q_liq, q_ice = S.split_q_c(q_c, T)   # same units as q_c; T in K
```

### Loop over many simulations (no network until you touch each case)

```julia
sel = S.CloudBenchSelection(0:2, (1, 4), (:amip, :amip_p4k))
for s in sel                    # or: for s in S.each_simulation(sel)
    # s isa S.CloudBenchSimulation (default remote output)
end
```

`S.CloudBenchSelection()` with no arguments spans the full published catalog (500 × 4 months × 5 experiments).

### Drive ClimaAtmos with CloudBench forcing (extension)

With **`ClimaAtmos`** in the environment the extension loads automatically. It reuses ClimaAtmos's
GCM-driven (Shen et al. 2022) cache + tendency — the **same** forcing methodology (large-scale advection + subsidence +
height-dependent relaxation/nudging) the Swirl-LM CloudBench LES were run with — so the ClimaAtmos columns are comparable.

**In-memory (recommended; no files):**

```julia
using ClimaAtmos: ClimaAtmos
using SwirlLMCloudBench: SwirlLMCloudBench, Simulation as S

sim   = S.CloudBenchSimulation(10, 7, :amip)
setup = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(sim)   # initial conditions AND forcing from the sounding (downloads it once)

# pass `setup` straight to ClimaAtmos (alongside your usual grid / params / dt / t_end / output):
# asim = ClimaAtmos.AtmosSimulation{Float64}(; setup,
#            grid   = ClimaAtmos.ColumnGrid(Float64; z_elem = 60, z_max = 30000.0),
#            params = ClimaAtmos.ClimaAtmosParameters(Float64), ...)

# or build just the forcing object to attach to your own model/setup:
forcing = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(sim)                 # nudging ON (matches CloudBench)
forcing = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(sim; nudge = false)  # advection + subsidence only
```

Nudging is **on by default** (mirrors how CloudBench was run). For *exact* comparability also set ClimaAtmos's relaxation
parameters (`gcmdriven_scalar_relaxation_timescale`, `gcmdriven_momentum_relaxation_timescale`,
`gcmdriven_relaxation_{minimum,maximum}_height`) to the Swirl-LM CloudBench values (`tau_r_tropo`, `tau_r_wind`,
`z_i`, `z_r`).

**Through a file:**

```julia
SwirlLMCloudBench.write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!("forcing.nc", forcing)
forcing = SwirlLMCloudBench.read_ClimaAtmosSwirlLMCloudBenchForcing("forcing.nc")
```

For a portable NetCDF of the *raw* sounding with **CloudBench** names (`z`, `temperature`, `q_t`, …), use
`S.write_sounding_netcdf!` / `S.ensure_sounding_netcdf!` instead.

### Parallel sweeps (threads)

```julia
using OhMyThreads
SwirlLMCloudBench.cloudbench_tmap(f, collection)
```

### Parallel raw downloads (processes)

After `using Distributed` and `addprocs(...)` as needed, load the package on **every** worker (e.g.
`@everywhere using SwirlLMCloudBench`), then:

```julia
using Distributed, SwirlLMCloudBench
using SwirlLMCloudBench: Simulation as S

my_root = "/path/to/shared/raw_root"   # must exist on every worker
sel = S.CloudBenchSelection(0:2, (1,), (:amip,))
dirs = SwirlLMCloudBench.cloudbench_pmap_download_raw!(sel, my_root)

# Or with an explicit vector:
sims = collect(S.each_simulation(sel))
dirs = SwirlLMCloudBench.cloudbench_pmap_download_raw!(sims, my_root)
```

This is `pmap` over `SwirlLMCloudBench.Simulation.download_cloudbench_raw!`; keyword arguments `sounding`, `parameters`,
and `zarr` match that function. Returns a `Vector{String}` of simulation directory paths (same order as the inputs).

## Data layout and environment

- `data/` — default mirror for upstream CloudBench fields (gitignored).
- `scratch/` — caches, locks, derived files (gitignored).

Environment overrides:

- `SWIRL_LM_CLOUDBENCH_DATA_ROOT`
- `SWIRL_LM_CLOUDBENCH_CACHE_ROOT`
- `SWIRL_LM_CLOUDBENCH_RAW_ROOT` — parent directory for bucket-shaped raw downloads (default: Scratch space `cloudbench_raw` in the Julia depot)
- `SWIRL_LM_CLOUDBENCH_LOGGING` — set to `1` / `true` / `yes` before `using` to enable optional download/Zarr/NetCDF info messages by default (or call `cloudbench_logging!(true)` at runtime). Per-call override: pass `verbose=true` / `verbose=false` on functions that support it (`nothing` keeps the global default).

Routine downloads use **Scratch** (mutable, depot-local, grown incrementally). The full ~2 TB `data.zarr` is **streamed**
over HTTPS, never mirrored — [Pkg artifacts](https://pkgdocs.julialang.org/v1/artifacts/) are immutable, content-addressed
blobs fetched whole, a poor fit for a multi-terabyte store accessed in arbitrary subsets, which is why the cache is
rolled-own. The small sounding-CSV set (~50 MB raw / ~20 MB gzipped for all 10,000 cases) *is* a good artifact candidate;
a bundled soundings artifact for fast offline catalog queries is planned (see `gen/build_sounding_artifact.jl`).

**Precedence:** an explicit `root=` on download/load functions overrides `SWIRL_LM_CLOUDBENCH_RAW_ROOT`, which overrides the Scratch default.

## API overview (core)

| Submodule          | Role |
|--------------------|------|
| `Catalog`          | Case range `0:499`, months `(1, 4, 7, 10)`, `EXPERIMENTS` / `CloudBenchExperiment`, `gcs_path_segment` |
| `Paths`            | `package_root`, `default_data_root`, `default_cache_root` |
| `Config`           | `data_root()`, `cache_root()`, `raw_download_root()`, `parse_bool_env` |
| `CaseDirs`         | `resolved_case_dir(site_id, month, experiment; root=…)` (canonical bucket layout) |
| `Simulation` | `CloudBenchInstance`, `CloudBenchSimulation`, `CloudBenchMetadata{P,S}`, `CloudBenchMetadataEmpty`, `CloudBenchSimulationRemote`, `CloudBenchSimulationLoaded`, `CloudBenchSimulationRemoteLoaded`, output types (`RemoteCloudBenchZarrOutput`, `LocalCloudBenchMirrorOutput`), `load_cloudbench_simulation`, `CloudBenchSounding`, `CloudBenchParameters`, bucket URLs, `download_cloudbench_raw!`, `open_zarr`, `open_zarr_local`, sounding NetCDF, `CloudBenchSelection` |

The main module exports only the submodules `Catalog`, `Paths`, `Config`, `CaseDirs`, and `Simulation`. Names defined inside `Simulation` are not re-exported at package scope; use e.g. `using SwirlLMCloudBench: Simulation as S` (or fully qualified `SwirlLMCloudBench.Simulation.…` names) for simulation and I/O APIs.

## Tests

Tests use a Julia 1.12+ [Pkg workspace](https://julialang.org/blog/2025/10/julia-1-12-highlights/) (`test/Project.toml` is a workspace member). Run from the **package** directory (where the main `Project.toml` lives):

```bash
cd SwirlLMCloudBench.jl
julia --project=. -e 'using Pkg; Pkg.test()'
```

Use `--project=.` (the package directory). If the active project is `test/`, `Pkg.test()` resolves the wrong environment.

`ClimaAtmos` is not a test dependency; load it in your project to exercise that extension. `OhMyThreads` and `Distributed`
are loaded only in their extension test blocks.

Optional tests that contact the public bucket: set `CLOUDBENCH_NETWORK_TEST=1` when running `Pkg.test()`.
