"""
    Simulation

CloudBench **simulation-output** layout under the public `cloudbench-simulation-output` bucket: [`CloudBenchInstance`](@ref)
keys and [`CloudBenchSimulation`](@ref) (metadata + output backend), HTTPS URLs, `sounding.csv`, `parameters.json`, lazy Zarr via [`open_zarr`](@ref),
local path helpers ([`local_simulation_dir`](@ref), [`Config.raw_download_root`](@ref)), [`download_cloudbench_raw!`](@ref),
condensate helpers ([`split_q_c`](@ref)), sounding → grouped NetCDF, and lazy [`CloudBenchSelection`](@ref).

Building handles and iterating selections uses [`Catalog`](@ref) and known paths only — **no** Zarr metadata calls.
Remote access starts when you call [`ensure_cloudbench_sounding_local!`](@ref), [`download_cloudbench_raw!`](@ref), [`open_zarr`](@ref), or similar.

Optional progress messages: keyword `verbose=nothing` on I/O entry points (default: follow [`SwirlLMCloudBench.cloudbench_logging`](@ref)),
or globally via [`SwirlLMCloudBench.cloudbench_logging!`](@ref)(`true`) / `ENV[\"SWIRL_LM_CLOUDBENCH_LOGGING\"]`.
"""
module Simulation

using ..Catalog: Catalog
const _Pkg = Base.parentmodule(@__MODULE__)

include(joinpath(@__DIR__, "condensate.jl"))
include(joinpath(@__DIR__, "parameters.jl"))
include(joinpath(@__DIR__, "sounding.jl"))
include(joinpath(@__DIR__, "simulation.jl"))
include(joinpath(@__DIR__, "urls.jl"))
include(joinpath(@__DIR__, "raw_paths.jl"))
include(joinpath(@__DIR__, "download_util.jl"))
include(joinpath(@__DIR__, "sounding_download.jl"))
include(joinpath(@__DIR__, "zarr_dataset.jl"))
include(joinpath(@__DIR__, "sounding_netcdf.jl"))
include(joinpath(@__DIR__, "selection.jl"))
include(joinpath(@__DIR__, "raw_download.jl"))

end
