"""
    SwirlLMCloudBenchClimaAtmosExt

Loads when `ClimaAtmos` is available. Drives a single-column ClimaAtmos run with forcing derived
from a CloudBench **`sounding.csv`**, reusing ClimaAtmos's own GCM-driven (Shen et al. 2022) cache + tendency — the
**same forcing methodology** the Swirl-LM CloudBench LES were run with (large-scale horizontal advection + subsidence +
height-dependent relaxation/nudging toward the reference profiles). This makes ClimaAtmos columns comparable to CloudBench.

[`SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing`](@ref) builds a `CloudBenchForcing` from the sounding, and
[`SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup`](@ref) a `ClimaAtmosSwirlLMCloudBenchSetup` (initial conditions **and** forcing from that same
sounding) to pass straight to `ClimaAtmos.AtmosSimulation{FT}(; setup = …, grid, params, …)`.
[`SwirlLMCloudBench.write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!`](@ref) and
[`SwirlLMCloudBench.read_ClimaAtmosSwirlLMCloudBenchForcing`](@ref) carry a forcing through a file.

# Nudging / comparability

Nudging is **on by default** (mirrors how CloudBench was run); pass `nudge = false` for advection+subsidence only. For
*exact* comparability also set ClimaAtmos's relaxation parameters (`gcmdriven_scalar_relaxation_timescale`,
`gcmdriven_momentum_relaxation_timescale`, `gcmdriven_relaxation_{minimum,maximum}_height`) to the Swirl-LM CloudBench
values (`tau_r_tropo`, `tau_r_wind`, `z_i`, `z_r`).

The vertical advection is carried by subsidence (`w`) and by the horizontal-advective residual, as
[`Simulation.cloudbench_sounding_zt_matrices`](@ref) computes it.
"""
module SwirlLMCloudBenchClimaAtmosExt

using ClimaAtmos: ClimaAtmos
using NCDatasets: NCDatasets
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench


"""Installed `ClimaAtmos` version (for logs / provenance)."""
SwirlLMCloudBench.climaatmos_pkg_version() = Base.pkgversion(ClimaAtmos)

"""One entry of a ClimaParams override TOML: a value and its declared type."""
_toml_float(x) = Dict{String, Union{Float64,String}}("value" => Float64(x), "type" => "float")

"""
    ClimaAtmos_SwirlLMCloudBench_toml_overrides(experiment = :amip)

ClimaParams overrides putting a column on CloudBench's configuration, in the parsed-TOML shape
`create_toml_dict` takes:
`ClimaParams.create_toml_dict(FT; override_file = ClimaAtmos_SwirlLMCloudBench_toml_overrides(:amip_4xco2))`.

`experiment` selects that scenario's CO₂; the rest is common to the ensemble.

Every value the reference fixes is stated, including those that presently equal a ClimaParams default, so a change to
those defaults cannot move a column off the reference silently.

What CloudBench fixes and this cannot: its cloud optics — an effective radius diagnosed as a one-third power law in
liquid water content, with asymmetry factor 0.8, where ClimaAtmos assumes a constant radius and has no asymmetry
entry. `docs/cloudbench_contract.md` section 6 records it.
"""
function SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_toml_overrides(experiment = :amip)
    c = S.SWIRL_LM_CONSTANTS
    r = S.CLOUDBENCH_RELAXATION
    return Dict{String, Dict{String,Union{Float64,String}}}(
        # what distinguishes the five scenarios, with SST
        "CO2_fixed_value" => _toml_float(S.cloudbench_co2_vmr(experiment)),
        # ClimaParams' defaults here are Shen et al. (2022)'s, not CloudBench's
        "gcmdriven_scalar_relaxation_timescale" => _toml_float(r.tau_tropo),
        "gcmdriven_momentum_relaxation_timescale" => _toml_float(r.tau_wind),
        "gcmdriven_relaxation_minimum_height" => _toml_float(r.z_i),
        "gcmdriven_relaxation_maximum_height" => _toml_float(r.z_r),
        "gas_constant" => _toml_float(c.R_UNIVERSAL),
        "gas_constant_dry_air" => _toml_float(c.R_D),
        "isobaric_specific_heat_dry_air" => _toml_float(c.CP),
        "isochoric_specific_heat_dry_air" => _toml_float(c.CV),
        "adiabatic_exponent_dry_air" => _toml_float(c.R_D / c.CP),
        "molar_mass_dry_air" => _toml_float(c.DRY_AIR_MOL_MASS),
        "molar_mass_water" => _toml_float(c.WATER_MOL_MASS),
        "gravitational_acceleration" => _toml_float(c.G),
        "avogadro_constant" => _toml_float(c.AVOGADRO),
        # liquid fraction ramps linearly between these two temperatures
        "temperature_water_freeze" => _toml_float(S.CONDENSATE_T_FREEZE),
        "temperature_homogenous_nucleation" => _toml_float(S.CONDENSATE_T_ICENUC),
        "pow_icenuc" => _toml_float(1),
        "prescribed_cloud_droplet_number_concentration" =>
            _toml_float(S.CLOUDBENCH_MICROPHYSICS.n_droplets),
    )
end

"""
    ClimaAtmos_SwirlLMCloudBench_params(FT = Float64, experiment = :amip; overrides = ClimaAtmos_SwirlLMCloudBench_toml_overrides(experiment))

`ClimaAtmos.ClimaAtmosParameters` built with [`ClimaAtmos_SwirlLMCloudBench_toml_overrides`](@ref) applied.
"""
SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_params(
    ::Type{FT} = Float64,
    experiment = :amip;
    overrides = SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_toml_overrides(experiment),
) where {FT<:AbstractFloat} = ClimaAtmos.ClimaAtmosParameters(
    ClimaAtmos.CP.create_toml_dict(FT; override_file = overrides),
)

"""
    ClimaAtmos_SwirlLMCloudBench_params(sim_or_instance, FT = Float64; kwargs...)

Parameters for a case, taking the CO₂ from that case's own experiment.
"""
SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_params(inst::S.CloudBenchInstance, ::Type{FT} = Float64; kwargs...) where {FT<:AbstractFloat} =
    SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_params(FT, Symbol(inst.experiment); kwargs...)

SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_params(sim::S.CloudBenchSimulation, ::Type{FT} = Float64; kwargs...) where {FT<:AbstractFloat} =
    SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_params(S.cloudbench_instance(sim), FT; kwargs...)

# ===========================================================================
# CloudBenchForcing — in-memory GCM-driven forcing built from a sounding.
# Carries the source profiles; the cache below reproduces exactly the NamedTuple that
# `ClimaAtmos.external_forcing_cache(Y, ::GCMForcing, …)` returns, and the tendency delegates
# to ClimaAtmos's (cache-only) GCM/reanalysis tendency.
# ===========================================================================

abstract type AbstractClimaAtmosCloudBenchForcing end

"""
    CloudBenchForcing{FT,V}

In-memory ClimaAtmos external forcing built from a CloudBench sounding. Fields are source profiles on the sounding's
`z` grid (interpolated onto the model column at cache time): `dTdt_hadv`/`dqtdt_hadv` (horizontal advective tendencies),
`subsidence` (vertical velocity `w`), and the nudging targets `T`/`q_t`/`u`/`v`. `cos_zenith` and `toa_flux` are this
case's diurnally averaged GCM values, used by [`CloudBenchInsolation`](@ref). `nudge` toggles the Shen-style
relaxation.

Build with [`SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing`](@ref).
"""
struct ClimaAtmosSwirlLMCloudBenchForcing{FT <: AbstractFloat, V <: AbstractVector{FT}} <: AbstractClimaAtmosCloudBenchForcing
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
    ClimaAtmosSwirlLMCloudBenchForcing(sounding; cos_zenith, toa_flux, nudge=true, FT=Float64) -> CloudBenchForcing
    ClimaAtmosSwirlLMCloudBenchForcing(sim_or_instance; root=nothing, verbose=nothing, kwargs...) -> CloudBenchForcing

In-memory GCM-driven forcing from a [`Simulation.CloudBenchSounding`](@ref) (or a simulation/instance, whose files are
ensured local first). See the module docstring for the forcing methodology and `nudge`.

[`CloudBenchInsolation`](@ref) reads `cos_zenith` and `toa_flux`, so a bare sounding — which carries neither — must be
given both. From a simulation or instance they default to that case's `parameters.json`.
"""
function SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(
    sounding::S.CloudBenchSounding;
    cos_zenith::Real,
    toa_flux::Real,
    nudge::Bool = true,
    FT::Type{<:AbstractFloat} = Float64,
)
    m = S.cloudbench_sounding_zt_matrices(sounding, 1)   # steady sounding → single time column
    prof(x) = FT.(x[:, 1])
    return ClimaAtmosSwirlLMCloudBenchForcing{FT,Vector{FT}}(
        FT.(collect(sounding.z)),
        prof(m.temperature_horizontal_advective_tendency),
        prof(m.q_t_horizontal_advective_tendency),
        FT.(collect(sounding.w)),
        FT.(collect(sounding.T)),
        FT.(collect(sounding.q_t)),
        FT.(collect(sounding.u)),
        FT.(collect(sounding.v)),
        FT(cos_zenith),
        FT(toa_flux),
        nudge,
    )
end

"""Profile fields of a [`CloudBenchForcing`](@ref), in the order they are stored."""
const ClimaAtmosCloudBenchForcingProfiles =
    (:z, :dTdt_hadv, :dqtdt_hadv, :subsidence, :T, :q_t, :u, :v)

"""`units` and `long_name` of each field in [`ClimaAtmosCloudBenchForcingProfiles`](@ref)."""
const ClimaAtmosCloudBenchForcingAttributes = Dict(
    :z => ("m", "Height above the surface"),
    :dTdt_hadv => ("K s^-1", "Horizontal advective tendency of temperature"),
    :dqtdt_hadv =>
        ("kg kg^-1 s^-1", "Horizontal advective tendency of total water specific humidity"),
    :subsidence => ("m s^-1", "Large-scale vertical velocity"),
    :T => ("K", "GCM air temperature, the relaxation target"),
    :q_t => ("kg kg^-1", "GCM total water specific humidity, the relaxation target"),
    :u => ("m s^-1", "GCM zonal velocity, the relaxation target"),
    :v => ("m s^-1", "GCM meridional velocity, the relaxation target"),
)



"""
    write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!(path, forcing) -> path

Write a [`CloudBenchForcing`](@ref) to NetCDF, such that
[`SwirlLMCloudBench.read_ClimaAtmosSwirlLMCloudBenchForcing`](@ref) returns an equal object.
"""
function SwirlLMCloudBench.write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!(
    path::AbstractString,
    forcing::ClimaAtmosSwirlLMCloudBenchForcing;
    verbose::Union{Nothing,Bool} = nothing,
)
    FT = eltype(forcing.z)
    mkpath(dirname(abspath(path)))
    NCDatasets.NCDataset(path, "c") do ds
        NCDatasets.defDim(ds, "z", length(forcing.z))
        for name in ClimaAtmosCloudBenchForcingProfiles
            units, long_name = ClimaAtmosCloudBenchForcingAttributes[name]
            v = NCDatasets.defVar(
                ds, String(name), FT, ("z",);
                attrib = ["units" => units, "long_name" => long_name],
            )
            v[:] = getfield(forcing, name)
        end
        ds.attrib["cos_zenith"] = forcing.cos_zenith
        ds.attrib["toa_flux"] = forcing.toa_flux
        ds.attrib["nudge"] = Int(forcing.nudge)
    end
    SwirlLMCloudBench.cloudbench_info("Wrote CloudBench forcing"; verbose, path)
    return path
end

"""
    read_ClimaAtmosSwirlLMCloudBenchForcing(path; FT = Float64) -> CloudBenchForcing

Read a forcing written by [`SwirlLMCloudBench.write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!`](@ref).
"""
function SwirlLMCloudBench.read_ClimaAtmosSwirlLMCloudBenchForcing(
    path::AbstractString;
    FT::Type{<:AbstractFloat} = Float64,
)
    isfile(path) || error("no CloudBench forcing at $(path)")
    return NCDatasets.NCDataset(path, "r") do ds
        profiles = map(ClimaAtmosCloudBenchForcingProfiles) do name
            FT.(collect(ds[String(name)][:]))
        end
        ClimaAtmosSwirlLMCloudBenchForcing{FT,Vector{FT}}(
            profiles...,
            FT(ds.attrib["cos_zenith"]),
            FT(ds.attrib["toa_flux"]),
            Bool(ds.attrib["nudge"]),
        )
    end
end

function SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(
    sim::S.CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
    nudge::Bool = true,
    cos_zenith::Union{Nothing,Real} = nothing,
    toa_flux::Union{Nothing,Real} = nothing,
    FT::Type{<:AbstractFloat} = Float64,
)
    meta = S.load_cloudbench_simulation(
        S.cloudbench_instance(sim);
        root = root,
        verbose = verbose,
        sounding_eltype = FT,
    ).metadata
    return SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(
        meta.sounding;
        nudge,
        cos_zenith = something(cos_zenith, meta.parameters.zenith),
        toa_flux = something(toa_flux, meta.parameters.insolation),
        FT,
    )
end

SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(inst::S.CloudBenchInstance; kwargs...) =
    SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(S.CloudBenchSimulation(inst); kwargs...)

function ClimaAtmos.external_forcing_cache(Y, forcing::ClimaAtmosSwirlLMCloudBenchForcing, params, _)
    FT = ClimaAtmos.CC.Spaces.undertype(axes(Y.c))
    ᶜdTdt_hadv = similar(Y.c, FT)
    ᶜdqtdt_hadv = similar(Y.c, FT)
    ᶜT_nudge = similar(Y.c, FT)
    ᶜqt_nudge = similar(Y.c, FT)
    ᶜu_nudge = similar(Y.c, FT)
    ᶜv_nudge = similar(Y.c, FT)
    ᶜinv_τ_wind = similar(Y.c, FT)
    ᶜinv_τ_scalar = similar(Y.c, FT)
    ᶜls_subsidence = similar(Y.c, FT)
    toa_flux = similar(ClimaAtmos.CC.Fields.level(Y.c.ρ, 1), FT)
    cos_zenith = similar(ClimaAtmos.CC.Fields.level(Y.c.ρ, 1), FT)

    zc_gcm = ClimaAtmos.CC.Fields.coordinate_field(Y.c).z
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

# Composed from ClimaAtmos's shared forcing kernels, which are the single implementation of each term. Borrowing another
# forcing type for dispatch is what broke this before: `ExternalDrivenTVForcing` is parameterised on a ColumnDataset and
# its tendency destructures `forcing_terms`/`term_caches`, neither of which the cache above has.
function ClimaAtmos.external_forcing_tendency!(Yₜ, Y, p, t, ::ClimaAtmosSwirlLMCloudBenchForcing)
    (;
        ᶜdTdt_hadv,
        ᶜdqtdt_hadv,
        ᶜT_nudge,
        ᶜqt_nudge,
        ᶜu_nudge,
        ᶜv_nudge,
        ᶜinv_τ_wind,
        ᶜinv_τ_scalar,
        ᶜls_subsidence,
    ) = p.external_forcing

    ClimaAtmos.nudge_uv!(Yₜ, Y, p, ᶜu_nudge, ᶜv_nudge, ᶜinv_τ_wind)

    ᶜdTdt = p.scratch.ᶜtemp_scalar
    ᶜdqtdt = p.scratch.ᶜtemp_scalar_2
    ClimaAtmos.nudge_Tq!(ᶜdTdt, ᶜdqtdt, Y, p, ᶜT_nudge, ᶜqt_nudge, ᶜinv_τ_scalar)
    @. ᶜdTdt += ᶜdTdt_hadv
    @. ᶜdqtdt += ᶜdqtdt_hadv
    ClimaAtmos.apply_Tq_forcing!(Yₜ, Y, p, ᶜdTdt, ᶜdqtdt)

    ClimaAtmos.apply_subsidence_forcing!(Yₜ, Y, p, ᶜls_subsidence)
    return nothing
end

# ===========================================================================
# ClimaAtmosSwirlLMCloudBenchSetup — turnkey single-column setup (ICs + surface + forcing from one sounding).
# Pass directly: ClimaAtmos.AtmosSimulation{FT}(; setup = ClimaAtmosSwirlLMCloudBenchSetup(sounding), grid, params, …).
# Mirrors ClimaAtmos.Setups.GCMDriven but in-memory.
# ===========================================================================

"""
    ClimaAtmosSwirlLMCloudBenchSetup

A ClimaAtmos `Setups`-compatible single-column setup whose **initial conditions** (T, u, v, q_t, ρ) and **external
forcing** both come from one CloudBench sounding. Build with [`SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup`](@ref) and pass as
`ClimaAtmos.AtmosSimulation{FT}(; setup = …, grid, params)`.
"""
struct ClimaAtmosSwirlLMCloudBenchSetup{P,F<:ClimaAtmosSwirlLMCloudBenchForcing, FT}
    profiles::P
    forcing::F
    T_sfc::FT
    z0::FT
end

"""
    ClimaAtmosSwirlLMCloudBenchSetup(sounding; surface_temperature, z0=1e-4, FT=Float64, kwargs...) -> ClimaAtmosSwirlLMCloudBenchSetup
    ClimaAtmosSwirlLMCloudBenchSetup(sim_or_instance; root=nothing, verbose=nothing, kwargs...) -> ClimaAtmosSwirlLMCloudBenchSetup

Build a [`ClimaAtmosSwirlLMCloudBenchSetup`](@ref) (initial conditions + forcing) from a sounding/simulation. Remaining `kwargs`
(`nudge`, `cos_zenith`, `toa_flux`) are forwarded to [`SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing`](@ref).

`surface_temperature` is the **sea surface** temperature. Given a simulation or instance it comes from that case's
`parameters.json` `sst`, along with `zenith` and `insolation`; a bare sounding carries none of the three, so from one
of those `surface_temperature` must be passed. It is not defaulted to the lowest sounding level: that is the
temperature of the *air* at the first level, which is a different quantity and is generally colder over ocean.

`z0` is the momentum roughness length [m]; the default is open ocean. CloudBench spans land and ice sites too, so a
site that is not ocean needs its own.
"""
function SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(
    sounding::S.CloudBenchSounding;
    surface_temperature::Real,
    z0::Real = 1e-4,
    FT::Type{<:AbstractFloat} = Float64,
    kwargs...,
)
    forcing = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(sounding; FT = FT, kwargs...)
    profiles = ClimaAtmos.Setups.ColumnProfiles(
        FT.(collect(sounding.z)),
        FT.(collect(sounding.temperature)),
        FT.(collect(sounding.u)),
        FT.(collect(sounding.v)),
        FT.(collect(sounding.q_t)),
        FT.(collect(sounding.rho)),
    )
    return ClimaAtmosSwirlLMCloudBenchSetup(profiles, forcing, FT(surface_temperature), FT(z0))
end

# The case's own `parameters.json` carries `sst`, `zenith` and `insolation`; they are the surface temperature and the
# insolation this site was run with, so they are the defaults rather than something the caller has to look up.
function SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(
    sim::S.CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
    FT::Type{<:AbstractFloat} = Float64,
    surface_temperature::Union{Nothing,Real} = nothing,
    cos_zenith::Union{Nothing,Real} = nothing,
    toa_flux::Union{Nothing,Real} = nothing,
    kwargs...,
)
    meta = S.load_cloudbench_simulation(
        S.cloudbench_instance(sim);
        root = root,
        verbose = verbose,
        sounding_eltype = FT,
    ).metadata
    prm = meta.parameters
    return SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(
        meta.sounding;
        FT = FT,
        surface_temperature = something(surface_temperature, prm.sst),
        cos_zenith = something(cos_zenith, prm.zenith),
        toa_flux = something(toa_flux, prm.insolation),
        kwargs...,
    )
end

SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(inst::S.CloudBenchInstance; kwargs...) =
    SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(S.CloudBenchSimulation(inst); kwargs...)

ClimaAtmos.Setups.center_initial_condition(setup::ClimaAtmosSwirlLMCloudBenchSetup, local_geometry, params) =
    ClimaAtmos.Setups.column_profiles_ic(setup.profiles, local_geometry)

ClimaAtmos.Setups.external_forcing(setup::ClimaAtmosSwirlLMCloudBenchSetup, ::Type{FT}) where {FT} = setup.forcing

"""
    CloudBenchInsolation

Insolation from the case's own `cos_zenith` and `toa_flux`, which CloudBench set to the GCM's diurnally averaged TOA
insolation and insolation-weighted zenith angle for that location and month, and held fixed.
"""
struct ClimaAtmosSwirlLMCloudBenchInsolation <: ClimaAtmos.AbstractInsolation end

function ClimaAtmos.set_insolation_variables!(Y, p, t, ::ClimaAtmosSwirlLMCloudBenchInsolation)
    (; rrtmgp_solver) = p.radiation
    ClimaAtmos.RRTMGP.cos_zenith(rrtmgp_solver) .=
        ClimaAtmos.CC.Fields.field2array(p.external_forcing.cos_zenith)
    ClimaAtmos.RRTMGP.toa_sw_flux_dn(rrtmgp_solver) .=
        ClimaAtmos.CC.Fields.field2array(p.external_forcing.toa_flux)
    return nothing
end

ClimaAtmos.Setups.insolation_model(::ClimaAtmosSwirlLMCloudBenchSetup) = ClimaAtmosSwirlLMCloudBenchInsolation()

"""
    ClimaAtmos_SwirlLMCloudBench_callback_kwargs(; kwargs...)

`callback_kwargs` for `ClimaAtmos.AtmosSimulation`, refreshing RRTMGP on the cadence CloudBench used — 4 simulated
minutes, against ClimaAtmos's 6-hour default. Extra `kwargs` are passed through.
"""
SwirlLMCloudBench.ClimaAtmos_SwirlLMCloudBench_callback_kwargs(; kwargs...) = (;
    dt_rad = string(Int(S.CLOUDBENCH_RADIATION.update_interval), "secs"),
    kwargs...,
)

function ClimaAtmos.Setups.surface_condition(setup::ClimaAtmosSwirlLMCloudBenchSetup, params)
    FT = eltype(params)
    return (;
        flux_scheme = ClimaAtmos.Setups.MoninObukhov(; z0 = FT(setup.z0)),
        temperature = ClimaAtmos.Setups.AnalyticTemperature(Returns(FT(setup.T_sfc))),
        overrides = nothing,
    )
end


end # module
