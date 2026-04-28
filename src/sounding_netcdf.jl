using NCDatasets: NCDatasets

"""
    write_sounding_netcdf!(out_path, sounding, netcdf_group; verbose=nothing)

Write NetCDF **group** `netcdf_group` with CloudBench **`sounding.csv`** names (`z`, `theta_li`, …). Each variable is 1D
along dimension `z`.

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
    nz = length(sounding.z)
    nz >= 2 || error("sounding must have at least 2 levels")

    mkpath(dirname(out_path))
    NCDatasets.NCDataset(out_path, "c") do ds
        g = NCDatasets.defGroup(ds, netcdf_group)
        NCDatasets.defDim(g, "z", nz)

        function wvar!(name::AbstractString, data)
            NCDatasets.defVar(g, name, Float64, ("z",))[:] = data
        end
        wvar!("z", sounding.z)
        wvar!("theta_li", sounding.theta_li)
        wvar!("temperature", sounding.temperature)
        wvar!("q_t", sounding.q_t)
        wvar!("u", sounding.u)
        wvar!("v", sounding.v)
        wvar!("w", sounding.w)
        wvar!("T_adv_src", sounding.T_adv_src)
        wvar!("q_t_adv_src", sounding.q_t_adv_src)
        wvar!("T", sounding.T_column)
        wvar!("p", sounding.p)
        wvar!("rho", sounding.rho)
        wvar!("cld_frac", sounding.cld_frac)
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
