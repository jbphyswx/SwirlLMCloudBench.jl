"""
    SwirlLMCloudBenchClimaAtmosExt

Loads when `ClimaAtmos` is available. Drives a single-column ClimaAtmos run with forcing derived
from a CloudBench **`sounding.csv`**, reusing ClimaAtmos's own GCM-driven (Shen et al. 2022) cache + tendency — the
**same forcing methodology** the Swirl-LM CloudBench LES were run with (large-scale horizontal advection + subsidence +
height-dependent relaxation/nudging toward the reference profiles). This makes ClimaAtmos columns comparable to CloudBench.

Two entry points:

- **In-memory** [`SwirlLMCloudBench.cloudbench_forcing`](@ref) → a `CloudBenchForcing` that builds the GCM-driven cache
  directly from the sounding (no files), and [`SwirlLMCloudBench.cloudbench_setup`](@ref) → a `CloudBenchSetup`
  (initial conditions **and** forcing from the same sounding) you pass straight to
  `ClimaAtmos.AtmosSimulation{FT}(; setup = …, grid, params, …)`.
- **File-based** [`SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!`](@ref) /
  [`SwirlLMCloudBench.ensure_clima_gcm_forcing_netcdf!`](@ref) → a NetCDF in the upstream `GCMForcing` schema (grouped by
  `cfsite_number`) so stock `ClimaAtmos.GCMForcing(file, cfsite)` can read it.

# Nudging / comparability

Nudging is **on by default** (mirrors how CloudBench was run); pass `nudge = false` for advection+subsidence only. For
*exact* comparability also set ClimaAtmos's relaxation parameters (`gcmdriven_scalar_relaxation_timescale`,
`gcmdriven_momentum_relaxation_timescale`, `gcmdriven_relaxation_{minimum,maximum}_height`) to the Swirl-LM CloudBench
values (`tau_r_tropo`, `tau_r_wind`, `z_i`, `z_r`).

CloudBench provides no Shen vertical-eddy decomposition (`tntva`/`tnhusva`), so those eddy terms are zero here; the
vertical advection is carried by subsidence (`w`) and the horizontal-advective residual exactly as
[`Simulation.cloudbench_sounding_zt_matrices`](@ref) computes it.
"""
module SwirlLMCloudBenchClimaAtmosExt

using ClimaAtmos: ClimaAtmos
using NCDatasets: NCDatasets
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench


"""Installed `ClimaAtmos` version (for logs / provenance)."""
SwirlLMCloudBench.climaatmos_pkg_version() = Base.pkgversion(ClimaAtmos)

# ===========================================================================
# CloudBenchForcing — in-memory GCM-driven forcing built from a sounding.
# Carries the source profiles; the cache below reproduces exactly the NamedTuple that
# `ClimaAtmos.external_forcing_cache(Y, ::GCMForcing, …)` returns, and the tendency delegates
# to ClimaAtmos's (cache-only) GCM/reanalysis tendency.
# ===========================================================================

"""
    CloudBenchForcing{FT,V}

In-memory ClimaAtmos external forcing built from a CloudBench sounding. CA.CC.Fields are source profiles on the sounding's
`z` grid (interpolated onto the model column at cache time): `dTdt_hadv`/`dqtdt_hadv` (horizontal advective tendencies),
`subsidence` (vertical velocity `w`), and the nudging targets `T`/`q_t`/`u`/`v`. Scalars `cos_zenith` / `toa_flux` are
used only by GCM-driven RRTMGP insolation (default `NaN`; set them if you enable that radiation). `nudge` toggles the
Shen-style relaxation.

Build with [`SwirlLMCloudBench.cloudbench_forcing`](@ref).
"""
struct CloudBenchForcing{FT <: AbstractFloat, V <: AbstractVector{FT}}
    z::V
    dTdt_hadv::V
    dqtdt_hadv::V
    subsidence::V
    T::V
    q_t::V
    u::V
    v::V
    cos_zenith::FT
    toa_flux::FT
    nudge::Bool
end

"""
    cloudbench_forcing(sounding; nudge=true, cos_zenith=NaN, toa_flux=NaN, FT=Float64) -> CloudBenchForcing
    cloudbench_forcing(sim_or_instance; root=nothing, verbose=nothing, kwargs...) -> CloudBenchForcing

In-memory GCM-driven forcing from a [`Simulation.CloudBenchSounding`](@ref) (or a simulation/instance, whose
`sounding.csv` is ensured local first). See the module docstring for the forcing methodology and `nudge`.
"""
function SwirlLMCloudBench.cloudbench_forcing(
    sounding::S.CloudBenchSounding;
    nudge::Bool = true,
    cos_zenith::Real = NaN,
    toa_flux::Real = NaN,
    FT::Type{<:AbstractFloat} = Float64,
)
    m = S.cloudbench_sounding_zt_matrices(sounding, 1)   # steady sounding → single time column
    prof(x) = FT.(x[:, 1])
    return CloudBenchForcing{FT,Vector{FT}}(
        FT.(collect(sounding.z)),
        prof(m.temperature_horizontal_advective_tendency),
        prof(m.q_t_horizontal_advective_tendency),
        FT.(collect(sounding.w)),
        FT.(collect(sounding.temperature)),
        FT.(collect(sounding.q_t)),
        FT.(collect(sounding.u)),
        FT.(collect(sounding.v)),
        FT(cos_zenith),
        FT(toa_flux),
        nudge,
    )
end

function SwirlLMCloudBench.cloudbench_forcing(
    sim::S.CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
    nudge::Bool = true,
    cos_zenith::Real = NaN,
    toa_flux::Real = NaN,
    FT::Type{<:AbstractFloat} = Float64,
)
    csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    snd = S.CloudBenchSounding(csv; eltype = FT)
    return SwirlLMCloudBench.cloudbench_forcing(snd; nudge, cos_zenith, toa_flux, FT)
end

SwirlLMCloudBench.cloudbench_forcing(inst::S.CloudBenchInstance; kwargs...) =
    SwirlLMCloudBench.cloudbench_forcing(S.CloudBenchSimulation(inst); kwargs...)

function ClimaAtmos.external_forcing_cache(Y, forcing::CloudBenchForcing, params, _)
    FT = CA.CC.Spaces.undertype(axes(Y.c))
    ᶜdTdt_fluc = similar(Y.c, FT)
    ᶜdqtdt_fluc = similar(Y.c, FT)
    ᶜdTdt_hadv = similar(Y.c, FT)
    ᶜdqtdt_hadv = similar(Y.c, FT)
    ᶜT_nudge = similar(Y.c, FT)
    ᶜqt_nudge = similar(Y.c, FT)
    ᶜu_nudge = similar(Y.c, FT)
    ᶜv_nudge = similar(Y.c, FT)
    ᶜinv_τ_wind = similar(Y.c, FT)
    ᶜinv_τ_scalar = similar(Y.c, FT)
    ᶜls_subsidence = similar(Y.c, FT)
    toa_flux = similar(CA.CC.Fields.level(Y.c.ρ, 1), FT)
    cos_zenith = similar(CA.CC.Fields.level(Y.c.ρ, 1), FT)

    zc_gcm = CA.CC.Fields.coordinate_field(Y.c).z
    z_src = forcing.z
    setprof!(field, prof) =
        (parent(field) .= ClimaAtmos.interp_vertical_prof(zc_gcm, z_src, prof); nothing)

    setprof!(ᶜdTdt_hadv, forcing.dTdt_hadv)
    setprof!(ᶜdqtdt_hadv, forcing.dqtdt_hadv)
    setprof!(ᶜls_subsidence, forcing.subsidence)
    setprof!(ᶜT_nudge, forcing.T)
    setprof!(ᶜqt_nudge, forcing.q_t)
    setprof!(ᶜu_nudge, forcing.u)
    setprof!(ᶜv_nudge, forcing.v)

    # CloudBench has no Shen vertical-eddy decomposition (tntva/tnhusva) → no eddy fluctuation term.
    fill!(parent(ᶜdTdt_fluc), 0)
    fill!(parent(ᶜdqtdt_fluc), 0)

    if forcing.nudge
        @. ᶜinv_τ_wind = ClimaAtmos.compute_gcm_driven_momentum_inv_τ(zc_gcm, params)
        @. ᶜinv_τ_scalar = ClimaAtmos.compute_gcm_driven_scalar_inv_τ(zc_gcm, params)
    else
        fill!(parent(ᶜinv_τ_wind), 0)
        fill!(parent(ᶜinv_τ_scalar), 0)
    end

    fill!(parent(toa_flux), forcing.toa_flux)
    fill!(parent(cos_zenith), forcing.cos_zenith)

    return (;
        ᶜdTdt_fluc,
        ᶜdqtdt_fluc,
        ᶜdTdt_hadv,
        ᶜdqtdt_hadv,
        ᶜT_nudge,
        ᶜqt_nudge,
        ᶜu_nudge,
        ᶜv_nudge,
        ᶜinv_τ_wind,
        ᶜinv_τ_scalar,
        ᶜls_subsidence,
        toa_flux,
        cos_zenith,
    )
end

# The GCM/reanalysis tendency reads only `p.external_forcing` (the cache above) — the forcing object is used purely for
# dispatch. We build the identical cache, so delegate to ClimaAtmos's own physics (a dummy ExternalDrivenTVForcing
# selects that method; its unused path field is irrelevant here).
function ClimaAtmos.external_forcing_tendency!(Yₜ, Y, p, t, ::CloudBenchForcing)
    FT = CA.CC.Spaces.undertype(axes(Y.c))
    return ClimaAtmos.external_forcing_tendency!(
        Yₜ,
        Y,
        p,
        t,
        ClimaAtmos.ExternalDrivenTVForcing{FT}(""),
    )
end

# ===========================================================================
# CloudBenchSetup — turnkey single-column setup (ICs + surface + forcing from one sounding).
# Pass directly: ClimaAtmos.AtmosSimulation{FT}(; setup = cloudbench_setup(sounding), grid, params, …).
# Mirrors ClimaAtmos.Setups.GCMDriven but in-memory.
# ===========================================================================

"""
    CloudBenchSetup

A ClimaAtmos `Setups`-compatible single-column setup whose **initial conditions** (T, u, v, q_t, ρ) and **external
forcing** both come from one CloudBench sounding. Build with [`SwirlLMCloudBench.cloudbench_setup`](@ref) and pass as
`ClimaAtmos.AtmosSimulation{FT}(; setup = …, grid, params)`.
"""
struct CloudBenchSetup{P,F<:CloudBenchForcing,FT}
    profiles::P
    forcing::F
    T_sfc::FT
end

"""
    cloudbench_setup(sounding; surface_temperature=sounding.temperature[1], FT=Float64, kwargs...) -> CloudBenchSetup
    cloudbench_setup(sim_or_instance; root=nothing, verbose=nothing, kwargs...) -> CloudBenchSetup

Build a [`CloudBenchSetup`](@ref) (initial conditions + forcing) from a sounding/simulation. `surface_temperature`
sets the prescribed surface temperature (default: lowest sounding level). Remaining `kwargs` (`nudge`, `cos_zenith`,
`toa_flux`) are forwarded to [`SwirlLMCloudBench.cloudbench_forcing`](@ref).
"""
function SwirlLMCloudBench.cloudbench_setup(
    sounding::S.CloudBenchSounding;
    surface_temperature::Real = sounding.temperature[1],
    FT::Type{<:AbstractFloat} = Float64,
    kwargs...,
)
    forcing = SwirlLMCloudBench.cloudbench_forcing(sounding; FT = FT, kwargs...)
    profiles = ClimaAtmos.Setups.ColumnProfiles(
        FT.(collect(sounding.z)),
        FT.(collect(sounding.temperature)),
        FT.(collect(sounding.u)),
        FT.(collect(sounding.v)),
        FT.(collect(sounding.q_t)),
        FT.(collect(sounding.rho)),
    )
    return CloudBenchSetup(profiles, forcing, FT(surface_temperature))
end

function SwirlLMCloudBench.cloudbench_setup(
    sim::S.CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
    FT::Type{<:AbstractFloat} = Float64,
    kwargs...,
)
    csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    snd = S.CloudBenchSounding(csv; eltype = FT)
    return SwirlLMCloudBench.cloudbench_setup(snd; FT = FT, kwargs...)
end

SwirlLMCloudBench.cloudbench_setup(inst::S.CloudBenchInstance; kwargs...) =
    SwirlLMCloudBench.cloudbench_setup(S.CloudBenchSimulation(inst); kwargs...)

ClimaAtmos.Setups.center_initial_condition(setup::CloudBenchSetup, local_geometry, params) =
    ClimaAtmos.Setups.column_profiles_ic(setup.profiles, local_geometry)

ClimaAtmos.Setups.external_forcing(setup::CloudBenchSetup, ::Type{FT}) where {FT} = setup.forcing

function ClimaAtmos.Setups.surface_condition(setup::CloudBenchSetup, params)
    FT = eltype(params)
    return (;
        flux_scheme = ClimaAtmos.Setups.MoninObukhov(; z0 = FT(1e-4)),
        temperature = ClimaAtmos.Setups.AnalyticTemperature(Returns(FT(setup.T_sfc))),
        overrides = nothing,
    )
end

# ===========================================================================
# File-based path: write a GCMForcing-schema NetCDF from a sounding.
# Variables/dims match ClimaAtmos's reader (`gcm_height` → "zg"; `gcm_driven_profile_tmean` over (z,time);
# `gcm_driven_timeseries` over (time,)), grouped by `cfsite_number`.
# ===========================================================================

"""
    write_clima_gcm_forcing_sounding_netcdf!(out_path, sounding, cfsite_number; nt=2, rsdt=NaN, coszen=NaN, verbose=nothing)

Write a NetCDF group `cfsite_number` in the upstream **`GCMForcing`** schema from a [`Simulation.CloudBenchSounding`](@ref),
so `ClimaAtmos.GCMForcing{FT}(out_path, cfsite_number)` reads it. Profiles (`zg, ta, hus, ua, va, alpha, tntha, tnhusha,
tntva, tnhusva, wap`) are written on `(z, time)`; `ts, rsdt, coszen` on `(time,)`. The advective tendencies (`tntha`,
`tnhusha`) and `wap` come from [`Simulation.cloudbench_sounding_zt_matrices`](@ref); the Shen eddy terms `tntva`/`tnhusva`
are zero (CloudBench provides none). Profiles are constant in time (steady sounding); `rsdt`/`coszen` default to `NaN`
(set them if you use GCM-driven insolation).
"""
function SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(
    out_path::AbstractString,
    sounding::S.CloudBenchSounding,
    cfsite_number::AbstractString;
    nt::Int = 2,
    rsdt::Real = NaN,
    coszen::Real = NaN,
    verbose::Union{Nothing,Bool} = nothing,
)
    nt >= 1 || error("nt must be >= 1")
    nz = length(sounding.z)
    nz >= 2 || error("sounding must have at least 2 levels")
    m = S.cloudbench_sounding_zt_matrices(sounding, nt)

    alpha = 1.0 ./ Float64.(collect(sounding.rho))
    zvec = Float64.(collect(sounding.z))
    ts0 = Float64(sounding.temperature[1])
    rep(profile) = repeat(reshape(Float64.(profile), nz, 1), 1, nt)
    zeros_zt = zeros(nz, nt)
    var_zt = Dict{String,Matrix{Float64}}(
        "zg" => rep(zvec),
        "ta" => Float64.(m.temperature),
        "hus" => Float64.(m.q_t),
        "ua" => Float64.(m.u),
        "va" => Float64.(m.v),
        "alpha" => rep(alpha),
        "tntha" => Float64.(m.temperature_horizontal_advective_tendency),
        "tnhusha" => Float64.(m.q_t_horizontal_advective_tendency),
        "tntva" => zeros_zt,
        "tnhusva" => zeros_zt,
        "wap" => Float64.(m.vertical_pressure_velocity),
    )

    mkpath(dirname(out_path))
    NCDatasets.NCDataset(out_path, "c") do ds
        g = NCDatasets.defGroup(ds, cfsite_number)
        NCDatasets.defDim(g, "z", nz)
        NCDatasets.defDim(g, "time", nt)
        for (name, data) in var_zt
            NCDatasets.defVar(g, name, Float64, ("z", "time"))[:, :] = data
        end
        NCDatasets.defVar(g, "ts", Float64, ("time",))[:] = fill(ts0, nt)
        NCDatasets.defVar(g, "rsdt", Float64, ("time",))[:] = fill(Float64(rsdt), nt)
        NCDatasets.defVar(g, "coszen", Float64, ("time",))[:] = fill(Float64(coszen), nt)
    end
    SwirlLMCloudBench.cloudbench_info(
        "Wrote ClimaAtmos GCMForcing NetCDF from CloudBench sounding";
        verbose,
        out_path,
        cfsite_number,
    )
    return out_path
end

"""
    ensure_clima_gcm_forcing_netcdf!(out_path, sim, cfsite_number; root=nothing, kwargs...)

Ensure `sounding.csv` is local, then write the [`GCMForcing`](@ref)-schema NetCDF at `out_path` unless it already
exists. `sim` may be a [`Simulation.CloudBenchInstance`](@ref) or [`Simulation.CloudBenchSimulation`](@ref). `kwargs`
(`nt`, `rsdt`, `coszen`, `verbose`) forward to [`SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!`](@ref).
"""
function SwirlLMCloudBench.ensure_clima_gcm_forcing_netcdf!(
    out_path::AbstractString,
    sim::S.CloudBenchSimulation,
    cfsite_number::AbstractString;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
    kwargs...,
)
    isfile(out_path) && return out_path
    csv = S.ensure_cloudbench_sounding_local!(sim; root = root, verbose = verbose)
    return SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(
        out_path,
        S.CloudBenchSounding(csv),
        cfsite_number;
        verbose = verbose,
        kwargs...,
    )
end

SwirlLMCloudBench.ensure_clima_gcm_forcing_netcdf!(
    out_path::AbstractString,
    inst::S.CloudBenchInstance,
    cfsite_number::AbstractString;
    kwargs...,
) = SwirlLMCloudBench.ensure_clima_gcm_forcing_netcdf!(
    out_path,
    S.CloudBenchSimulation(inst),
    cfsite_number;
    kwargs...,
)

end # module
