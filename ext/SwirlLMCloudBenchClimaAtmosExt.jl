"""
    SwirlLMCloudBenchClimaAtmosExt

Loads when `ClimaAtmos` is available. Defines [`SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!`](@ref) and
related helpers on the parent module.

Helpers wire CloudBench **`sounding.csv`** into ClimaAtmos workflows using **explicit** arguments: a [`CloudBenchInstance`](@ref)
or [`CloudBenchSimulation`](@ref), paths, and NetCDF group names. Read your YAML or experiment config in application code,
then call these functions with scalars and paths.

# Column forcing NetCDF (this extension only)

[`ensure_clima_sounding_netcdf!`](@ref) writes a **GCM-style external column forcing** layout (variable names such as
`zg`, `ta`, `hus`, …) that matches what ClimaAtmos `GCMDriven` / `GCMForcing` expects under `external_forcing_file`, **not**
the CloudBench CSV names. For NetCDF that mirrors `sounding.csv`, use [`Simulation.write_sounding_netcdf!`](@ref) /
[`Simulation.ensure_sounding_netcdf!`](@ref) in the base package.

ClimaAtmos chooses forcing types (`GCMForcing`, `ExternalDrivenTVForcing`, …) from your case configuration. For
`GCMDriven` / `GCMForcing`, parsed configs often use `cfsite_number` as the NetCDF **group** name and
`external_forcing_file` for the file path — use [`SwirlLMCloudBench.merge_clima_gcmdriven_forcing_keys!`](@ref) to copy
those from an overlay dict.

# ClimaAtmos users

- Set the NetCDF **group** string to match what your case expects (often the same value you put in `cfsite_number` for
  `GCMForcing`).
- Set `external_forcing_file` to the absolute or project-relative path of the grouped NetCDF file.
"""
module SwirlLMCloudBenchClimaAtmosExt

using ClimaAtmos: ClimaAtmos
using NCDatasets: NCDatasets
using SwirlLMCloudBench
using SwirlLMCloudBench: Simulation as S

const DEFAULT_FORCING_BASENAME = "cloudbench_column_forcing.nc"

"""Installed `ClimaAtmos` version string (for logs)."""
function SwirlLMCloudBench.climaatmos_pkg_version()
    return Base.pkgversion(ClimaAtmos)
end

"""
    clima_column_forcing_overlay(; netcdf_group, external_forcing_file=nothing) -> Dict{String,Any}

String-keyed fragment to merge into a single-column case dict: [`CLIMA_COLUMN_OVERLAY_NETCDF_GROUP_KEY`](@ref) and,
when provided, `external_forcing_file`. Uses `ENV[\"SWIRL_LM_CLOUDBENCH_EXTERNAL_FORCING_FILE\"]` when set from
[`prepare_climaatmos_cloudbench_worktree!`](@ref).
"""
function SwirlLMCloudBench.clima_column_forcing_overlay(;
    netcdf_group::AbstractString,
    external_forcing_file::Union{Nothing,AbstractString} = nothing,
)
    out = Dict{String,Any}()
    out[SwirlLMCloudBench.CLIMA_COLUMN_OVERLAY_NETCDF_GROUP_KEY] = string(netcdf_group)
    if external_forcing_file !== nothing
        s = strip(string(external_forcing_file))
        !isempty(s) && (out["external_forcing_file"] = s)
    end
    return out
end

"""
    write_clima_gcm_forcing_sounding_netcdf!(out_path, sounding, netcdf_group; nt=48, rsdt_const=400.0, coszen_const=0.85, verbose=nothing)

Write grouped NetCDF for **ClimaAtmos external column forcing** (GCM-style names), from [`CloudBenchSounding`](@ref).

Maps CloudBench columns into CMIP-like names: `z`→`zg`, `temperature`→`ta`, `q_t`→`hus`, winds unchanged as `ua`/`va`,
`specific_volume` `1/ρ` as `alpha`. Adds zero large-scale tendencies (`tntha`, …), zero `wap`, surface `ts` from lowest
level, and constant `rsdt` / `coszen` placeholders (not in CloudBench CSV — override for your case).

See also [`ensure_clima_sounding_netcdf!`](@ref).

`verbose` controls the completion message (`nothing` → [`cloudbench_logging`](@ref)).
"""
function SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(
    out_path::AbstractString,
    sounding::S.CloudBenchSounding,
    netcdf_group::AbstractString;
    nt::Int = 48,
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    verbose::Union{Nothing,Bool} = nothing,
)
    nt >= 1 || error("nt must be >= 1")
    z = sounding.z
    T = sounding.temperature
    q_t = sounding.q_t
    u = sounding.u
    v = sounding.v
    rho = sounding.rho
    nz = length(z)
    nz >= 2 || error("sounding must have at least 2 levels")

    alpha = 1.0 ./ rho
    ts0 = T[1]

    mkpath(dirname(out_path))
    NCDatasets.NCDataset(out_path, "c") do ds
        g = NCDatasets.defGroup(ds, netcdf_group)
        NCDatasets.defDim(g, "z", nz)
        NCDatasets.defDim(g, "time", nt)

        zg_a = zeros(nz, nt)
        ta_a = zeros(nz, nt)
        hus_a = zeros(nz, nt)
        ua_a = zeros(nz, nt)
        va_a = zeros(nz, nt)
        alpha_a = zeros(nz, nt)
        tn0 = zeros(nz, nt)
        wap_a = zeros(nz, nt)
        for j in 1:nt
            zg_a[:, j] .= z
            ta_a[:, j] .= T
            hus_a[:, j] .= q_t
            ua_a[:, j] .= u
            va_a[:, j] .= v
            alpha_a[:, j] .= alpha
        end

        for name in (
            "zg",
            "ta",
            "hus",
            "ua",
            "va",
            "alpha",
            "tntha",
            "tnhusha",
            "tntva",
            "tnhusva",
            "wap",
        )
            data = name == "zg" ? zg_a :
                   name == "ta" ? ta_a :
                   name == "hus" ? hus_a :
                   name == "ua" ? ua_a :
                   name == "va" ? va_a :
                   name == "alpha" ? alpha_a :
                   name == "wap" ? wap_a : tn0
            NCDatasets.defVar(g, name, Float64, ("z", "time"))[:] = data
        end

        NCDatasets.defVar(g, "ts", Float64, ("time",))[:] = fill(ts0, nt)
        NCDatasets.defVar(g, "rsdt", Float64, ("time",))[:] = fill(rsdt_const, nt)
        NCDatasets.defVar(g, "coszen", Float64, ("time",))[:] = fill(coszen_const, nt)
    end
    SwirlLMCloudBench.cloudbench_info("Wrote Clima GCM-style column forcing NetCDF from CloudBench sounding"; verbose, out_path, netcdf_group)
    return out_path
end

"""
    ensure_clima_sounding_netcdf!(out_path, sim, netcdf_group; kwargs...)

Ensure `sounding.csv` is local, then write **GCM-style** column forcing NetCDF at `out_path` unless it already exists
(see [`write_clima_gcm_forcing_sounding_netcdf!`](@ref)).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref). `kwargs` include `root` (forwarded to
[`ensure_cloudbench_sounding_local!`](@ref)) and `nt`, `rsdt_const`, `coszen_const`, `verbose` for the forcing file writer.
"""
function SwirlLMCloudBench.ensure_clima_sounding_netcdf!(
    out_path::AbstractString,
    sim::S.CloudBenchSimulation,
    netcdf_group::AbstractString;
    root::Union{Nothing,AbstractString} = nothing,
    nt::Int = 48,
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    verbose::Union{Nothing,Bool} = nothing,
)
    isfile(out_path) && return out_path
    sounding_csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    return SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(
        out_path,
        S.CloudBenchSounding(sounding_csv),
        netcdf_group;
        nt = nt,
        rsdt_const = rsdt_const,
        coszen_const = coszen_const,
        verbose = verbose,
    )
end

function SwirlLMCloudBench.ensure_clima_sounding_netcdf!(
    out_path::AbstractString,
    inst::S.CloudBenchInstance,
    netcdf_group::AbstractString;
    kwargs...,
)
    return SwirlLMCloudBench.ensure_clima_sounding_netcdf!(out_path, S.CloudBenchSimulation(inst), netcdf_group; kwargs...)
end

"""
    prepare_climaatmos_cloudbench_worktree!(
        experiment_dir,
        sim;
        netcdf_group = "cloudbench_column",
        forcing_relpath = joinpath("reference", "cloudbench_column_forcing.nc"),
        write_forcing = true,
        kwargs...,
    ) -> NamedTuple

Ensure local **`sounding.csv`**. If `write_forcing`, write **GCM-style** column forcing NetCDF at
`joinpath(experiment_dir, forcing_relpath)` unless that file already exists (unless `forcing_relpath` is absolute). Returns
`sim`, `sounding_csv_path`, `forcing_path`, and `column_forcing_overlay`.

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).

`root` is passed to [`ensure_cloudbench_sounding_local!`](@ref). `nt`, `rsdt_const`, `coszen_const`, and `verbose` are passed to
[`write_clima_gcm_forcing_sounding_netcdf!`](@ref) when a new forcing file is created.
"""
function SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!(
    experiment_dir::AbstractString,
    sim::S.CloudBenchSimulation;
    netcdf_group::AbstractString = "cloudbench_column",
    forcing_relpath::AbstractString = joinpath("reference", DEFAULT_FORCING_BASENAME),
    write_forcing::Bool = true,
    root::Union{Nothing,AbstractString} = nothing,
    nt::Int = 48,
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    verbose::Union{Nothing,Bool} = nothing,
)
    sounding_path = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    forcing_path = nothing
    if write_forcing
        fr = string(forcing_relpath)
        out_path = isabspath(fr) ? fr : joinpath(experiment_dir, fr)
        mkpath(dirname(out_path))
        if !isfile(out_path)
            forcing_path = SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(
                out_path,
                S.CloudBenchSounding(sounding_path),
                netcdf_group;
                nt = nt,
                rsdt_const = rsdt_const,
                coszen_const = coszen_const,
                verbose = verbose,
            )
        else
            forcing_path = out_path
        end
    end
    gfo = strip(get(ENV, "SWIRL_LM_CLOUDBENCH_EXTERNAL_FORCING_FILE", ""))
    ext_file = if !isempty(gfo)
        gfo
    elseif forcing_path !== nothing
        forcing_path
    else
        nothing
    end
    overlay = SwirlLMCloudBench.clima_column_forcing_overlay(; netcdf_group, external_forcing_file = ext_file)
    return (; sim, sounding_csv_path = sounding_path, forcing_path, column_forcing_overlay = overlay)
end

function SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!(
    experiment_dir::AbstractString,
    inst::S.CloudBenchInstance;
    kwargs...,
)
    return SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!(
        experiment_dir,
        S.CloudBenchSimulation(inst);
        kwargs...,
    )
end

"""
    merge_clima_cloudbench_overlay!(config_dict::Dict, overlay::AbstractDict)

Merge string-keyed `overlay` into `config_dict` in place.
"""
function SwirlLMCloudBench.merge_clima_cloudbench_overlay!(config_dict::Dict, overlay::AbstractDict)
    for (k, v) in overlay
        config_dict[string(k)] = v
    end
    return config_dict
end

"""
    merge_clima_gcmdriven_forcing_keys!(config_dict::Dict, overlay::AbstractDict)

For `GCMDriven` / `GCMForcing`, set `cfsite_number` and `external_forcing_file` from `overlay` when present.
"""
function SwirlLMCloudBench.merge_clima_gcmdriven_forcing_keys!(config_dict::Dict, overlay::AbstractDict)
    kgrp = SwirlLMCloudBench.CLIMA_COLUMN_OVERLAY_NETCDF_GROUP_KEY
    if haskey(overlay, kgrp)
        config_dict["cfsite_number"] = overlay[kgrp]
    end
    if haskey(overlay, "external_forcing_file")
        config_dict["external_forcing_file"] = overlay["external_forcing_file"]
    end
    return config_dict
end

end
