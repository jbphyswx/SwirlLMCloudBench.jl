using NCDatasets: NCDatasets

"""
    write_sounding_netcdf!(out_path, sounding, netcdf_group; verbose=nothing)

Write NetCDF **group** `netcdf_group` with the same field names as CloudBench `sounding.csv`: `z`, `temperature`, `q_t`,
`u`, `v`, `rho`. Each variable is 1D along dimension `z` (the sounding is a single vertical column, not a time series).

# Dimensions

- `z`: number of sounding levels.

`verbose` controls the completion message (`nothing` → [`cloudbench_logging`](@ref)).
"""
function write_sounding_netcdf!(
    out_path::AbstractString,
    sounding::CloudBenchSounding,
    netcdf_group::AbstractString;
    verbose::Union{Nothing,Bool} = nothing,
)
    z = sounding.z
    T = sounding.temperature
    q_t = sounding.q_t
    u = sounding.u
    v = sounding.v
    rho = sounding.rho
    nz = length(z)
    nz >= 2 || error("sounding must have at least 2 levels")

    mkpath(dirname(out_path))
    NCDatasets.NCDataset(out_path, "c") do ds
        g = NCDatasets.defGroup(ds, netcdf_group)
        NCDatasets.defDim(g, "z", nz)

        NCDatasets.defVar(g, "z", Float64, ("z",))[:] = z
        NCDatasets.defVar(g, "temperature", Float64, ("z",))[:] = T
        NCDatasets.defVar(g, "q_t", Float64, ("z",))[:] = q_t
        NCDatasets.defVar(g, "u", Float64, ("z",))[:] = u
        NCDatasets.defVar(g, "v", Float64, ("z",))[:] = v
        NCDatasets.defVar(g, "rho", Float64, ("z",))[:] = rho
    end
    _Pkg.cloudbench_info("Wrote CloudBench sounding-based NetCDF"; verbose, out_path, netcdf_group)
    return out_path
end

function write_sounding_netcdf!(
    out_path::AbstractString,
    sounding_csv_path::AbstractString,
    netcdf_group::AbstractString;
    verbose::Union{Nothing,Bool} = nothing,
)
    return write_sounding_netcdf!(
        out_path,
        CloudBenchSounding(sounding_csv_path),
        netcdf_group;
        verbose = verbose,
    )
end

"""
    ensure_sounding_netcdf!(out_path, sim, netcdf_group; root=nothing, verbose=nothing)

Ensure `sounding.csv` is local, then call [`write_sounding_netcdf!`](@ref) unless `out_path` already exists.

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref). `root` is forwarded to
[`ensure_cloudbench_sounding_local!`](@ref) (`nothing` → [`raw_download_root`](@ref)). `verbose` applies to download and
write messages for this call (`nothing` → [`cloudbench_logging`](@ref)).
"""
function ensure_sounding_netcdf!(
    out_path::AbstractString,
    sim::CloudBenchSimulation,
    netcdf_group::AbstractString;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    isfile(out_path) && return out_path
    sounding_csv = ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    return write_sounding_netcdf!(out_path, sounding_csv, netcdf_group; verbose = verbose)
end

function ensure_sounding_netcdf!(
    out_path::AbstractString,
    inst::CloudBenchInstance,
    netcdf_group::AbstractString;
    kwargs...,
)
    return ensure_sounding_netcdf!(out_path, CloudBenchSimulation(inst), netcdf_group; kwargs...)
end
