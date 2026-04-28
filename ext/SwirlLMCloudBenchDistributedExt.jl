"""
    SwirlLMCloudBenchDistributedExt

Loads when `Distributed` is loaded. Provides [`SwirlLMCloudBench.cloudbench_pmap_download_raw!`](@ref) to download
many CloudBench simulations in parallel with `pmap`.

Workers must be able to run [`Simulation.download_cloudbench_raw!`](@ref) (load this package on every worker,
e.g. `@everywhere using SwirlLMCloudBench`).
"""
module SwirlLMCloudBenchDistributedExt

using Distributed: Distributed
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench

_as_instance(x::S.CloudBenchInstance) = x
_as_instance(s::S.CloudBenchSimulation) = S.cloudbench_instance(s)

"""
    cloudbench_pmap_download_raw!(sims, root::AbstractString; sounding=true, parameters=true, zarr=false, verbose=nothing)

[`Distributed.pmap`](@ref) over `sims`: each worker calls [`download_cloudbench_raw!`](@ref)(`inst`; `root`, `sounding`,
`parameters`, `zarr`, `verbose`) with the catalog key `inst`. Returns a `Vector{String}` of per-simulation directory paths (same order as `sims`).

`sims` may be a vector of [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref) (only the key is serialized / used).
"""
function SwirlLMCloudBench.cloudbench_pmap_download_raw!(
    sims::AbstractVector,
    root::AbstractString;
    sounding::Bool = true,
    parameters::Bool = true,
    zarr::Bool = false,
    verbose::Union{Nothing,Bool} = nothing,
)
    r = String(normpath(expanduser(String(root))))
    isempty(sims) && return String[]
    return Distributed.pmap(sims) do sim
        inst = _as_instance(sim)
        S.download_cloudbench_raw!(inst; root = r, sounding, parameters, zarr, verbose)
    end
end

"""
    cloudbench_pmap_download_raw!(sel::CloudBenchSelection, root::AbstractString; kwargs...)

Materialize [`each_simulation`](@ref)(`sel`) and call [`cloudbench_pmap_download_raw!(sims, root; kwargs...)`](@ref).
"""
function SwirlLMCloudBench.cloudbench_pmap_download_raw!(
    sel::S.CloudBenchSelection,
    root::AbstractString;
    kwargs...,
)
    sims = collect(S.each_simulation(sel))
    return SwirlLMCloudBench.cloudbench_pmap_download_raw!(sims, root; kwargs...)
end

end
