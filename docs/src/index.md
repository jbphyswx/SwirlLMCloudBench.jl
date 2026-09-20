# SwirlLMCloudBench.jl

Julia utilities for the Google [Swirl-LM](https://github.com/google-research/swirl-lm)
[CloudBench](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)
ensemble: catalog constants, bucket URLs, a mutable download cache, lazy `data.zarr` access, parsed
`sounding.csv` / `parameters.json`, and (with `ClimaAtmos` loaded) single-column forcing helpers.

See the [README](https://github.com/jbphyswx/SwirlLMCloudBench.jl) for a task-oriented guide, and the
[API](@ref) page for the full reference.

## Submodules

- [`Catalog`](@ref SwirlLMCloudBench.Catalog) — case indices (`0:499`), seasonal months `(1, 4, 7, 10)`, experiment IDs.
- [`Paths`](@ref SwirlLMCloudBench.Paths) — package-relative default roots.
- [`Config`](@ref SwirlLMCloudBench.Config) — `ENV`-driven `data_root` / `cache_root` / `raw_download_root`.
- [`CaseDirs`](@ref SwirlLMCloudBench.CaseDirs) — `resolved_case_dir` (canonical bucket layout).
- [`Simulation`](@ref SwirlLMCloudBench.Simulation) — instances, simulations, URLs, downloads, Zarr, soundings, selection.

## Thermodynamics

At package scope, [`SWIRL_LM_CONSTANTS`](@ref SwirlLMCloudBench.SWIRL_LM_CONSTANTS) and
[`SWIRL_LM_WATER`](@ref SwirlLMCloudBench.SWIRL_LM_WATER) carry the constants and the
water-thermodynamics parameters the CloudBench LES ran with, and
[`DefaultThermodynamicsBackend`](@ref SwirlLMCloudBench.DefaultThermodynamicsBackend)
implements Swirl-LM's `water.py` on them — saturation vapor
pressure, the liquid-fraction ramp, potential temperatures and the saturation adjustment — with no
external thermodynamics dependency. With `Thermodynamics` loaded, a `ThermodynamicsParameters` set
serves as a backend for the same functions.

## Data layout and caching

Routine downloads use a mutable, depot-local [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) cache
(or `SWIRL_LM_CLOUDBENCH_RAW_ROOT`) laid out as the public bucket `[root]/[site_id]/[month]/[experiment]/`. The
full ~2 TB `data.zarr` store is **streamed** lazily over HTTPS rather than mirrored; `Pkg.Artifacts` is not used for
it (artifacts are immutable, fetched-whole blobs — a poor fit for a multi-terabyte store accessed in arbitrary subsets).
