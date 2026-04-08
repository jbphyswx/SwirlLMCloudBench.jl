using Zarr: Zarr
using ..Catalog: Catalog

"""
    open_zarr(sim)
    open_zarr(site_id, month, experiment=:amip)

Open the public `data.zarr` for this simulation over HTTPS. This is the first **remote** Zarr touch (metadata / chunk map);
arrays remain lazy until indexed.

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).

`experiment` may be a catalog `Symbol`, a segment string such as `\"amip-p4k\"`, or [`Catalog.CloudBenchExperiment`](@ref).

`verbose` controls the open message for this call only (`nothing` → [`cloudbench_logging`](@ref)).
"""
function open_zarr(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,String,Catalog.CloudBenchExperiment} = :amip;
    verbose::Union{Nothing,Bool} = nothing,
)
    path = cloudbench_zarr_url(site_id, month, experiment)
    _Pkg.cloudbench_info("Opening CloudBench Zarr (lazy)"; verbose, path)
    try
        return Zarr.zopen(path; consolidated = true)
    catch
        return Zarr.zopen(path)
    end
end

open_zarr(inst::CloudBenchInstance; verbose::Union{Nothing,Bool} = nothing) =
    open_zarr(inst.site_id, inst.month, inst.experiment; verbose)

open_zarr(sim::CloudBenchSimulation; verbose::Union{Nothing,Bool} = nothing) =
    open_zarr(cloudbench_instance(sim); verbose)

"""
    open_zarr_local(inst, root)
    open_zarr_local(simulation, root)
    open_zarr_local(simulation)

Open a **local** `data.zarr` directory at [`zarr_local_path`](@ref)(`inst`, `root`). Errors if that directory does not exist.

When `simulation` is a [`CloudBenchSimulation`](@ref) with [`LocalCloudBenchMirrorOutput`](@ref), uses that output’s
`root` (same as `open_zarr_local(cloudbench_instance(simulation), simulation.output.root)`).

Downloading the full remote Zarr store into that path is not supported; use [`open_zarr`](@ref) for HTTPS access.

`verbose` controls the open message for this call only (`nothing` → [`cloudbench_logging`](@ref)).
"""
function open_zarr_local(
    inst::CloudBenchInstance,
    root::AbstractString;
    verbose::Union{Nothing,Bool} = nothing,
)
    path = zarr_local_path(inst, root)
    isdir(path) || error("local Zarr store not found at $(path)")
    _Pkg.cloudbench_info("Opening local CloudBench Zarr (lazy)"; verbose, path)
    try
        return Zarr.zopen(path; consolidated = true)
    catch
        return Zarr.zopen(path)
    end
end

open_zarr_local(sim::CloudBenchSimulation, root::AbstractString; verbose::Union{Nothing,Bool} = nothing) =
    open_zarr_local(cloudbench_instance(sim), root; verbose)

function open_zarr_local(sim::CloudBenchSimulation; verbose::Union{Nothing,Bool} = nothing)
    sim.output isa LocalCloudBenchMirrorOutput ||
        throw(
            ArgumentError(
                "open_zarr_local(simulation) requires simulation.output isa LocalCloudBenchMirrorOutput; " *
                "use open_zarr_local(cloudbench_instance(simulation), root) or open_zarr(simulation) for remote HTTPS access",
            ),
        )
    return open_zarr_local(cloudbench_instance(sim), sim.output.root; verbose)
end
