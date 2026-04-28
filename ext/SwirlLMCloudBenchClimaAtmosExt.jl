"""
    SwirlLMCloudBenchClimaAtmosExt

Loads when `ClimaAtmos` is available. Defines [`SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!`](@ref) and
related helpers on the parent module.

Helpers wire CloudBench **`sounding.csv`** into ClimaAtmos workflows using **explicit** arguments: a [`Simulation.CloudBenchInstance`](@ref)
or [`Simulation.CloudBenchSimulation`](@ref), paths, and NetCDF group names. Read your YAML or experiment config in application code,
then call these functions with scalars and paths.

# Column forcing NetCDF (this extension only)

[`SwirlLMCloudBench.ensure_clima_sounding_netcdf!`](@ref) writes a **GCM-style external column forcing** layout (variable names such as
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
using ClimaCore: Fields, Spaces
using ClimaUtilities: TimeVaryingInputs as TVIs
using ClimaUtilities.Utils: isequispaced, wrap_time
using Dates: Dates
using Interpolations: Interpolations
using NCDatasets: NCDatasets
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench

const DEFAULT_FORCING_BASENAME = "cloudbench_column_forcing.nc"

# ---------------------------------------------------------------------------
# In-memory (z, time) column forcing for `ProvidedColumnTVForcing`
# ---------------------------------------------------------------------------
# `ClimaUtilities.TimeVaryingInput` for 2D files is file-oriented. This type
# implements the same `AbstractTimeVaryingInput` + `evaluate!` contract for
# `ta`, `hus`, etc. on a column, from `Matrix` data and a source `z` column
# (e.g. from `CloudBenchSounding`) with time + vertical interpolation matching
# `TimeVaryingInput(...; method=LinearInterpolation(PeriodicCalendar()))` on
# a flat NetCDF with the same `z` and `time` axes (no disk I/O).
# ---------------------------------------------------------------------------

struct InMemoryColumnTimeVaryingInput{FT, S, M <: TVIs.AbstractInterpolationMethod} <:
       TVIs.AbstractTimeVaryingInput
    z_src::Vector{FT}
    t_sec::Vector{FT}
    data::Matrix{FT}
    center_space::S
    method::M
    z_model::Vector{FT}
end

function InMemoryColumnTimeVaryingInput(
    z_src::Vector{FT},
    t_sec::Vector{FT},
    data::Matrix{FT},
    center_space,
    method = TVIs.LinearInterpolation(TVIs.PeriodicCalendar()),
) where {FT <: AbstractFloat}
    size(data, 1) == length(z_src) ||
        error("InMemoryColumnTimeVaryingInput: data rows must match z_src (got size(data,1)=$(size(data,1)), length(z_src)=$(length(z_src)))")
    size(data, 2) == length(t_sec) ||
        error("InMemoryColumnTimeVaryingInput: data columns must match t_sec (got size(data,2)=$(size(data,2)), length(t_sec)=$(length(t_sec)))")
    length(t_sec) >= 2 || error("InMemoryColumnTimeVaryingInput: need at least two time samples for linear interpolation")
    TVIs.extrapolation_bc(method) isa TVIs.PeriodicCalendar ||
        error("InMemoryColumnTimeVaryingInput: only PeriodicCalendar outer time behavior is implemented (use LinearInterpolation(PeriodicCalendar()))")
    isequispaced(t_sec) || error("InMemoryColumnTimeVaryingInput: times must be equispaced for PeriodicCalendar (same as file-based `TimeVaryingInput`)")
    issorted(z_src) || error("InMemoryColumnTimeVaryingInput: z_src must be increasing (sort the source column)")

    z_model = _column_model_level_z(FT, center_space)
    return InMemoryColumnTimeVaryingInput{FT, typeof(center_space), typeof(method)}(
        z_src, t_sec, data, center_space, method, z_model,
    )
end

"""Extract center height (m) for each cell, in `FT`, for a 1D column `center_space`."""
function _column_model_level_z(FT, center_space)
    f0 = Fields.zeros(FT, center_space)
    zc = Fields.coordinate_field(f0).z
    return Vector{FT}(vec(Array(parent(zc))))
end

function _column_profile_both_in_time(
    t_column::InMemoryColumnTimeVaryingInput{FT},
    t::FT,
) where {FT}
    (; t_sec, data) = t_column
    t_init = t_sec[1]
    t_end = t_sec[end]
    dt = t_sec[2] - t_sec[1]
    w = wrap_time(t, t_init, t_end + dt)
    nt = length(t_sec)
    if w > t_end
        c2 = (w - t_end) / dt
        c1 = one(FT) - c2
        return @view(data[:, end]), @view(data[:, 1]), c1, c2
    end
    i = searchsortedlast(t_sec, w)
    i = clamp(i, 1, nt - 1)
    t0, t1 = t_sec[i], t_sec[i + 1]
    c2 = (w - t0) / (t1 - t0)
    c1 = one(FT) - c2
    return @view(data[:, i]), @view(data[:, i + 1]), c1, c2
end

function _regrid_column_to_model!(dest, t_column::InMemoryColumnTimeVaryingInput, p0, p1, c1, c2)
    (; z_src, z_model) = t_column
    FT = eltype(z_model)
    n = length(p0)
    n == length(p1) == length(z_src) || error("length mismatch in source column")
    @inbounds for j in 1:n
        isfinite(p0[j]) && isfinite(p1[j]) || error("non-finite source data in InMemoryColumnTimeVaryingInput")
    end
    itp0 = Interpolations.extrapolate(
        Interpolations.interpolate(
            (z_src,),
            Vector{FT}(p0),
            Interpolations.Gridded(Interpolations.Linear()),
        ),
        Interpolations.Flat(),
    )
    itp1 = Interpolations.extrapolate(
        Interpolations.interpolate(
            (z_src,),
            Vector{FT}(p1),
            Interpolations.Gridded(Interpolations.Linear()),
        ),
        Interpolations.Flat(),
    )
    pd = vec(parent(dest))
    length(pd) == length(z_model) || error(
        "InMemoryColumnTimeVaryingInput: model level count does not match destination field storage",
    )
    @inbounds for k in eachindex(z_model)
        zq = z_model[k]
        v = c1 * itp0(zq) + c2 * itp1(zq)
        pd[k] = v
    end
    return nothing
end

function TVIs.evaluate!(
    dest,
    t_column::InMemoryColumnTimeVaryingInput{FT},
    time::Number,
) where {FT}
    tF = FT(time)
    p0, p1, c1, c2 = _column_profile_both_in_time(t_column, tF)
    _regrid_column_to_model!(dest, t_column, p0, p1, c1, c2)
    return nothing
end

"""Installed `ClimaAtmos` version string (for logs)."""
function SwirlLMCloudBench.climaatmos_pkg_version()
    return Base.pkgversion(ClimaAtmos)
end

"""
    clima_column_forcing_overlay(; netcdf_group, external_forcing_file=nothing) -> Dict{String,Any}

String-keyed fragment to merge into a single-column case dict: [`SwirlLMCloudBench.CLIMA_COLUMN_OVERLAY_NETCDF_GROUP_KEY`](@ref) and,
when provided, `external_forcing_file`. Uses `ENV[\"SWIRL_LM_CLOUDBENCH_EXTERNAL_FORCING_FILE\"]` when set from
[`SwirlLMCloudBench.prepare_climaatmos_cloudbench_worktree!`](@ref).
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

Write grouped NetCDF for **ClimaAtmos external column forcing** (GCM-style names), from [`Simulation.CloudBenchSounding`](@ref).

Maps CloudBench columns into names expected by ClimaAtmos GCM-style column forcing: `z`→`zg`, `temperature`→`ta`, `q_t`→`hus`, winds as `ua`/`va`,
`specific_volume` `1/ρ` as `alpha`. Adds zero large-scale tendencies (`tntha`, …), zero `wap`, surface `ts` from lowest
level, and constant `rsdt` / `coszen` placeholders (not in CloudBench CSV — override for your case).

See also [`SwirlLMCloudBench.ensure_clima_sounding_netcdf!`](@ref).

`verbose` controls the completion message (`nothing` → [`SwirlLMCloudBench.cloudbench_logging`](@ref)).
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
(see [`SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!`](@ref)).

`sim` may be a [`Simulation.CloudBenchInstance`](@ref) or [`Simulation.CloudBenchSimulation`](@ref). `kwargs` include `root` (forwarded to
[`Simulation.ensure_cloudbench_sounding_local!`](@ref)) and `nt`, `rsdt_const`, `coszen_const`, `verbose` for the forcing file writer.
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

`sim` may be a [`Simulation.CloudBenchInstance`](@ref) or [`Simulation.CloudBenchSimulation`](@ref).

`root` is passed to [`Simulation.ensure_cloudbench_sounding_local!`](@ref). `nt`, `rsdt_const`, `coszen_const`, and `verbose` are passed to
[`SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!`](@ref) when a new forcing file is created.
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

function _tv_flat_nc_column_varstrings()
    return ["ta", "hus", "tntva", "wa", "tntha", "tnhusha", "ua", "va", "tnhusva", "rho", "wap"]
end

"""[`ProvidedColumnTVForcing`](@ref) / flat column-NetCDF short names (`ta`, `hus`, …) on `(z,time)` from [`Simulation.cloudbench_sounding_zt_matrices`](@ref).

[`Simulation.cloudbench_sounding_zt_matrices`](@ref) already exposes large-scale vertical advection as `temperature_vertical_advection` / `q_t_vertical_advection` and folds the same physics into `tntha`/`tnhusha` sources via the Swirl-style sum into `temperature_horizontal_advective_tendency` / `q_t_horizontal_advective_tendency`.

The variables `tntva` and `tnhusva` are **different** optional budget terms in this NetCDF schema (not the same as the Swirl subsidence stencil in the rows above); CloudBench does not populate them, so they are stored as zeros only to satisfy the file shape expected by [`ProvidedColumnTVForcing`](@ref)."""
function _provided_column_tv_namedtuple_from_cloudbench_zt(m)
    T = eltype(m.temperature)
    nz, nt = size(m.temperature)
    zmat = fill(T(0), nz, nt)
    return (;
        ta = m.temperature,
        hus = m.q_t,
        tntva = zmat,
        wa = m.w,
        tntha = m.temperature_horizontal_advective_tendency,
        tnhusha = m.q_t_horizontal_advective_tendency,
        ua = m.u,
        va = m.v,
        tnhusva = zmat,
        rho = m.rho,
        wap = m.vertical_pressure_velocity,
    )
end

"""
    write_clima_tv_flat_forcing_netcdf_from_sounding!(out_path, sounding, nt; kwargs...)

Write a **flat** (no NetCDF group) column forcing file compatible with
[`ClimaAtmos.ProvidedColumnTVForcing`](@ref) / [`SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc`](@ref),
using the short NetCDF column names (`ta`, `hus`, … on `(z,time)`) that [`ProvidedColumnTVForcing`](@ref) expects, plus surface scalars on `time`.
This is the time-varying layout read by `ClimaUtilities.TimeVaryingInput` (unlike
[`SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!`](@ref) which uses a labeled group for `GCMForcing`).

Per-variable ``(z,time)`` arrays come from [`Simulation.cloudbench_sounding_zt_matrices`](@ref) (`w`, `T_adv_src`, `q_t_adv_src`
from `sounding.csv`). `rsdt` / `coszen` / `ts` use the same placeholders as the GCM-style writer unless you post-process the file.

# Mapping `tntva` / `tnhusva`

[`Simulation.cloudbench_sounding_zt_matrices`](@ref) combines Swirl-style total advection and vertical (`vadv`) pieces into
`temperature_horizontal_advective_tendency` / `q_t_horizontal_advective_tendency`; those become `tntha` / `tnhusha` via [`_provided_column_tv_namedtuple_from_cloudbench_zt`](@ref).

The CliMA driver also expects **`tntva`** and **`tnhusva`** arrays on the same grid; CloudBench **`sounding.csv`** does not supply separate fields for those budgets, so this writer stores **zeros** for those variables only so the file schema matches [`ProvidedColumnTVForcing`](@ref)—not because subsidence physics was discarded (that physics is in `tntha`/`tnhusha` as above).

For callback wiring, see ClimaAtmos docs / your checkout’s `external_forcing.jl` for the column-TV path.
"""
function SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!(
    out_path::AbstractString,
    sounding::S.CloudBenchSounding,
    nt::Int;
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    verbose::Union{Nothing,Bool} = nothing,
)
    nt >= 1 || error("nt must be >= 1")
    z = sounding.z
    T = sounding.temperature
    nz = length(z)
    nz >= 2 || error("sounding must have at least 2 levels")
    ts0 = T[1]
    t_s = collect((0:nt-1) .* 3600.0)
    m = S.cloudbench_sounding_zt_matrices(sounding, nt)
    colvars = _provided_column_tv_namedtuple_from_cloudbench_zt(m)

    mkpath(dirname(out_path))
    NCDatasets.NCDataset(out_path, "c") do ds
        NCDatasets.defDim(ds, "z", nz)
        NCDatasets.defDim(ds, "time", nt)
        NCDatasets.defVar(ds, "time", Float64, ("time",))[:] = t_s
        NCDatasets.defVar(ds, "z", Float64, ("z",))[:] = collect(z)

        for name in _tv_flat_nc_column_varstrings()
            vmat = getproperty(colvars, Symbol(name))
            NCDatasets.defVar(ds, name, Float64, ("z", "time"))[:] = vmat
        end

        NCDatasets.defVar(ds, "ts", Float64, ("time",))[:] = fill(ts0, nt)
        NCDatasets.defVar(ds, "rsdt", Float64, ("time",))[:] = fill(rsdt_const, nt)
        NCDatasets.defVar(ds, "coszen", Float64, ("time",))[:] = fill(coszen_const, nt)
        NCDatasets.defVar(ds, "hfls", Float64, ("time",))[:] = zeros(nt)
        NCDatasets.defVar(ds, "hfss", Float64, ("time",))[:] = zeros(nt)
    end
    SwirlLMCloudBench.cloudbench_info(
        "Wrote flat TV column forcing NetCDF from CloudBench sounding";
        verbose,
        out_path,
    )
    return out_path
end

"""
    build_provided_column_tv_forcing_from_nc(center_space, surface_target_space, nc_path; reference_date)

Build [`ClimaAtmos.ProvidedColumnTVForcing`](@ref) by constructing [`ClimaUtilities.TimeVaryingInput`](@ref) readers on `nc_path`
for each column variable name expected by [`ProvidedColumnTVForcing`](@ref) (same names as the flat NetCDF written by [`write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref)).

The NetCDF must expose variables at dataset root (no group), typically produced by
[`SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref).

`surface_target_space` should match ClimaAtmos’ external forcing cache, i.e.
`axes(Fields.level(Y.f.u₃, half))` for your column state `Y`. Before allocating `Y`,
construct it from the column grid face space, e.g.
`ClimaCore.Spaces.level(face_space, ClimaCore.Utilities.half)` on the SCM vertical mesh.

`reference_date` must align with your [`ClimaAtmos.Setups.InterpolatedColumnProfile`](@ref) / simulation calendar when using periodic calendar interpolation on the file time axis.
"""
function SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc(
    center_space,
    surface_target_space,
    nc_path::AbstractString;
    reference_date::Dates.DateTime = Dates.DateTime(1979, 1, 1),
)
    extrapolation_bc = (Interpolations.Flat(), Interpolations.Flat(), Interpolations.Linear())
    meth = TVIs.LinearInterpolation(TVIs.PeriodicCalendar())

    function tv_col(name::AbstractString)
        TVIs.TimeVaryingInput(
            nc_path,
            name,
            center_space;
            reference_date = reference_date,
            regridder_kwargs = (; extrapolation_bc),
            method = meth,
        )
    end
    function tv_surf(name::AbstractString)
        TVIs.TimeVaryingInput(
            nc_path,
            name,
            surface_target_space;
            reference_date = reference_date,
            regridder_kwargs = (; extrapolation_bc),
            method = meth,
        )
    end

    cv = _tv_flat_nc_column_varstrings()
    column_nt = (; (Symbol(c) => tv_col(c) for c in cv)...)
    surf_vars = ("coszen", "rsdt", "hfls", "hfss", "ts")
    surface_nt = (; (Symbol(s) => tv_surf(s) for s in surf_vars)...)
    return ClimaAtmos.ProvidedColumnTVForcing(column_nt, surface_nt)
end

"""
Build [`ClimaAtmos.ProvidedColumnTVForcing`](@ref) from a CloudBench sounding **in memory** (no NetCDF I/O), using
the extension-local column TVI type for each column key and the 0D [`ClimaUtilities.TimeVaryingInput`](@ref)(`times`, `values`)
pattern for each surface key, with the same LinearInterpolation(PeriodicCalendar()) default and the same
duplicate-sounding-in-time semantics as [`SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref).

Column matrices come from [`Simulation.cloudbench_sounding_zt_matrices`](@ref); this function maps them through [`_provided_column_tv_namedtuple_from_cloudbench_zt`](@ref) onto the short names (`ta`, `hus`, …) required by [`ProvidedColumnTVForcing`](@ref), zero-filling slots CloudBench does not provide (`tntva`, `tnhusva`).

Budget-slot semantics vs [`ProvidedColumnTVForcing`](@ref) mirror [`write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref).

Center and surface target spaces should match the ClimaAtmos TV forcing cache; for file-based construction
see [`SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc`](@ref) on the same module.
"""
function SwirlLMCloudBench.build_provided_column_tv_forcing_from_cloudbench_sounding(
    center_space,
    surface_target_space,
    sounding::S.CloudBenchSounding,
    nt::Int;
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    column_method = TVIs.LinearInterpolation(TVIs.PeriodicCalendar()),
    surface_method = TVIs.LinearInterpolation(TVIs.PeriodicCalendar()),
)
    nt >= 2 || error("nt must be >= 2 for linear time interpolation (PeriodicCalendar)")
    z = sounding.z
    nz = length(z)
    nz >= 2 || error("sounding must have at least 2 levels")
    T = sounding.temperature
    ts0 = T[1]
    FT = Spaces.undertype(center_space)
    z_src = Vector{FT}(z)
    t_sec = [FT(3600) * FT(i) for i in 0:(nt - 1)]
    isequispaced(t_sec) || error("internal: non-uniform time grid (this is a bug)")

    m = S.cloudbench_sounding_zt_matrices(sounding, nt)
    e5 = _provided_column_tv_namedtuple_from_cloudbench_zt(m)
    toft(a) = Matrix{FT}(a)
    ta_a = toft(e5.ta)
    hus_a = toft(e5.hus)
    ua_a = toft(e5.ua)
    va_a = toft(e5.va)
    rho_a = toft(e5.rho)
    tnt = toft(e5.tntva)
    wa_a = toft(e5.wa)
    tntha_a = toft(e5.tntha)
    tnhusha_a = toft(e5.tnhusha)
    tnhusva_a = toft(e5.tnhusva)
    wap_a = toft(e5.wap)

    col = (;
        :ta => InMemoryColumnTimeVaryingInput(z_src, t_sec, ta_a, center_space, column_method),
        :hus => InMemoryColumnTimeVaryingInput(z_src, t_sec, hus_a, center_space, column_method),
        :tntva => InMemoryColumnTimeVaryingInput(z_src, t_sec, tnt, center_space, column_method),
        :wa => InMemoryColumnTimeVaryingInput(z_src, t_sec, wa_a, center_space, column_method),
        :tntha => InMemoryColumnTimeVaryingInput(z_src, t_sec, tntha_a, center_space, column_method),
        :tnhusha => InMemoryColumnTimeVaryingInput(z_src, t_sec, tnhusha_a, center_space, column_method),
        :ua => InMemoryColumnTimeVaryingInput(z_src, t_sec, ua_a, center_space, column_method),
        :va => InMemoryColumnTimeVaryingInput(z_src, t_sec, va_a, center_space, column_method),
        :tnhusva => InMemoryColumnTimeVaryingInput(z_src, t_sec, tnhusva_a, center_space, column_method),
        :rho => InMemoryColumnTimeVaryingInput(z_src, t_sec, rho_a, center_space, column_method),
        :wap => InMemoryColumnTimeVaryingInput(z_src, t_sec, wap_a, center_space, column_method),
    )

    tsv = fill(FT(ts0), nt)
    rsv = fill(FT(rsdt_const), nt)
    cosv = fill(FT(coszen_const), nt)
    hfls = fill(FT(0), nt)
    hfss = fill(FT(0), nt)
    sur = (;
        :coszen => TVIs.TimeVaryingInput(t_sec, cosv; method = surface_method),
        :rsdt => TVIs.TimeVaryingInput(t_sec, rsv; method = surface_method),
        :hfls => TVIs.TimeVaryingInput(t_sec, hfls; method = surface_method),
        :hfss => TVIs.TimeVaryingInput(t_sec, hfss; method = surface_method),
        :ts => TVIs.TimeVaryingInput(t_sec, tsv; method = surface_method),
    )
    return ClimaAtmos.ProvidedColumnTVForcing(col, sur)
end

"""
    cloudbench_provided_column_tv_forcing(center_space, surface_target_space, sim; kwargs...)

Build ClimaAtmos [`ClimaAtmos.ProvidedColumnTVForcing`](@ref) from a CloudBench simulation (after ensuring **`sounding.csv`** is local).

# Behavior

- **Default (in memory):** build column and surface `AbstractTimeVaryingInput` objects with
  [`SwirlLMCloudBench.build_provided_column_tv_forcing_from_cloudbench_sounding`](@ref) — no flat TV NetCDF read or write.

- **`netcdf_path` to an existing file:** if that path is a flat TV column NetCDF (layout from
  [`SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref) or the same variable/dim contract), use
  [`SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc`](@ref) (e.g. reanalysis, a prebuilt file, or a cache from a prior run).

- **`netcdf_path` set but the file is missing:** with **`persist_flat_tv_netcdf = false`** (default), the path
  is ignored and the in-memory builder is used. With **`persist_flat_tv_netcdf = true`**, the flat file is
  written to that path from the sounding, then the result is built from the file (on-disk cache or exchange
  with other tools).

To write a flat TV NetCDF only, call [`SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!`](@ref) from application code.
"""
function SwirlLMCloudBench.cloudbench_provided_column_tv_forcing(
    center_space,
    surface_target_space,
    sim::S.CloudBenchSimulation;
    netcdf_path::Union{Nothing,AbstractString} = nothing,
    persist_flat_tv_netcdf::Bool = false,
    root::Union{Nothing,AbstractString} = nothing,
    nt::Int = 48,
    reference_date::Dates.DateTime = Dates.DateTime(1979, 1, 1),
    rsdt_const::Float64 = 400.0,
    coszen_const::Float64 = 0.85,
    verbose::Union{Nothing,Bool} = nothing,
    column_method = TVIs.LinearInterpolation(TVIs.PeriodicCalendar()),
    surface_method = TVIs.LinearInterpolation(TVIs.PeriodicCalendar()),
)
    if netcdf_path !== nothing
        p = abspath(string(netcdf_path))
        if isfile(p)
            return SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc(
                center_space,
                surface_target_space,
                p;
                reference_date = reference_date,
            )
        elseif persist_flat_tv_netcdf
            sounding_csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
            SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!(
                p,
                S.CloudBenchSounding(sounding_csv),
                nt;
                rsdt_const = rsdt_const,
                coszen_const = coszen_const,
                verbose = verbose,
            )
            return SwirlLMCloudBench.build_provided_column_tv_forcing_from_nc(
                center_space,
                surface_target_space,
                p;
                reference_date = reference_date,
            )
        end
    end
    sounding_csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    return SwirlLMCloudBench.build_provided_column_tv_forcing_from_cloudbench_sounding(
        center_space,
        surface_target_space,
        S.CloudBenchSounding(sounding_csv),
        nt;
        rsdt_const = rsdt_const,
        coszen_const = coszen_const,
        column_method = column_method,
        surface_method = surface_method,
    )
end

function SwirlLMCloudBench.cloudbench_provided_column_tv_forcing(
    center_space,
    surface_target_space,
    inst::S.CloudBenchInstance;
    kwargs...,
)
    return SwirlLMCloudBench.cloudbench_provided_column_tv_forcing(
        center_space,
        surface_target_space,
        S.CloudBenchSimulation(inst);
        kwargs...,
    )
end

end
