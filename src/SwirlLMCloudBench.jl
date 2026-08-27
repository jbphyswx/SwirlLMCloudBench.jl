"""
    SwirlLMCloudBench

Julia utilities for [Swirl-LM CloudBench](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)
ensemble outputs: catalog constants (cases, months, experiments), configurable local data roots, stable path helpers,
and access to published **`sounding.csv`** / **`data.zarr`** via submodule [`Simulation`](@ref).

Registered **dependencies** include `Zarr`, `CSV`, `Downloads`, `NCDatasets`, `JSON`, and `Scratch` (default raw download cache).
**`SwirlLMCloudBenchOhMyThreadsExt`** loads when you use `OhMyThreads` (threaded helpers over collections).
**`SwirlLMCloudBenchDistributedExt`** loads when you use `Distributed` (parallel raw downloads via [`cloudbench_pmap_download_raw!`](@ref)).
See `README.md`.

# Submodules

- `Catalog` — valid case indices (`0:499`), seasonal months, experiment IDs.
- `Paths` — package-relative defaults (`package_root`, `default_data_root`, `default_cache_root`).
- `Config` — `ENV`-driven `data_root` / `cache_root` / `raw_download_root` (Scratch-backed default for raw bucket mirror layout).
- `CaseDirs` — `resolved_case_dir` (canonical bucket layout `[root]/[site_id]/[month]/[experiment]/`) combining the above.
- `Simulation` — `CloudBenchInstance`, `CloudBenchSimulation`, URLs, lazy [`Simulation.open_zarr`](@ref), `CloudBenchSounding`,
  [`Simulation.write_sounding_netcdf!`](@ref) / [`Simulation.ensure_sounding_netcdf!`](@ref),
  [`Simulation.split_q_c`](@ref) (Swirl-LM liquid fraction on `q_c`), lazy [`Simulation.CloudBenchSelection`](@ref).

CloudBench labels simulations with integer **`site_id`** in `0:499`, months `{1,4,7,10}`, and experiment segments per
the upstream README.

# Environment variables

| Variable | Purpose |
|----------|---------|
| `SWIRL_LM_CLOUDBENCH_DATA_ROOT` | Override root for mirrored CloudBench data (default: `<package>/data`) |
| `SWIRL_LM_CLOUDBENCH_CACHE_ROOT` | Override scratch/cache directory (default: `<package>/scratch`) |
| `SWIRL_LM_CLOUDBENCH_RAW_ROOT` | Override parent directory for raw bucket layout downloads (`[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/`); when unset, uses [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) under the Julia depot |
| `SWIRL_LM_CLOUDBENCH_LOGGING` | If `1` / `true` / `yes` (case-insensitive), enable optional `@info`-style messages by default at load time; or use [`cloudbench_logging!`](@ref)(`true`). Per-call: `verbose=true` / `false` on supported APIs (`nothing` uses the global default). |

# Example

```julia
using SwirlLMCloudBench: Catalog, Config, CaseDirs

Catalog.n_cases()  # 500
CaseDirs.resolved_case_dir(0, 1, :amip)   # <data_root>/0/1/amip
```

For `Simulation` APIs, either call `SwirlLMCloudBench.Simulation.open_zarr(...)` or
`using SwirlLMCloudBench: Simulation as S` and use qualified names such as `S.open_zarr`.
"""
module SwirlLMCloudBench

include("logging.jl")
include("paths.jl")
include("catalog.jl")
include("config.jl")
include("case_dirs.jl")
include("simulation_output.jl")

export Catalog, Paths, Config, CaseDirs, Simulation

"""Same as `Catalog.CLOUDBENCH_CASE_INDICES` (case index range)."""
cases_range() = Catalog.CLOUDBENCH_CASE_INDICES

"""Same as `Catalog.CLOUDBENCH_MONTHS` (seasonal months tuple)."""
months_tuple() = Catalog.CLOUDBENCH_MONTHS

"""`Val.(Catalog.EXPERIMENTS)` for dispatch experiments."""
experiments_val() = Val.(Catalog.EXPERIMENTS)




# :: Extensions ::
# OhMyThreads / Distributed extensions:
function cloudbench_tmap end
function cloudbench_pmap_download_raw! end

include("ext/ClimaAtmosExt_bindings.jl")

end
