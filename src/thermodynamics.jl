# ============================================================================================ #
# Thermodynamics
#
# Swirl-LM's water thermodynamics, as the CloudBench LES ran it. The functions work directly on
# scalar fields — there is no thermodynamic state object — and the physics comes from a
# *backend* selected by dispatch on the first argument:
#
#   * `DefaultThermodynamicsBackend` (defined here) — Swirl-LM's own equations and constants,
#     with no external thermodynamics dependency.
#   * a backend added by a package extension, which dispatches these functions on its own
#     parameter set.
#
# Every constant is read from `SWIRL_LM_WATER` / `SWIRL_LM_CONSTANTS`, and every formula is
# cited to the line of `swirl_lm/physics/thermodynamics/water.py` it comes from.
# ============================================================================================ #

"""
    AbstractThermodynamicsBackend

Supertype for the built-in, dependency-free thermodynamics backend. Extension backends dispatch
on their own parameter set and need not subtype this.
"""
abstract type AbstractThermodynamicsBackend end
Base.broadcastable(backend::AbstractThermodynamicsBackend) = tuple(backend)

"""
    DefaultThermodynamicsBackend()

Swirl-LM's water thermodynamics on [`SWIRL_LM_WATER`](@ref): Rankine–Kirchhoff saturation vapor
pressure anchored at the triple point, a density-based saturation specific humidity, a linear
liquid-fraction ramp, and the secant saturation adjustment of
[`water.py`](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/physics/thermodynamics/water.py).

Swirl-LM's `use_fast_thermodynamics` solver — a coupled 2×2 Newton iteration on `(ρ, T)` — is
unset by default and is not implemented here.
"""
struct DefaultThermodynamicsBackend <: AbstractThermodynamicsBackend end

# --- generic methods: declared here, methods added per backend (default below; extension backends add theirs) --
"""Dry-air gas constant [J/kg/K]."""
function R_d end
"""Water-vapor gas constant [J/kg/K]."""
function R_v end
"""Gravitational acceleration [m/s^2]."""
function grav end
"""Dry-air isobaric heat capacity [J/kg/K]."""
function cp_d end
"""Dry-air isochoric heat capacity [J/kg/K]."""
function cv_d end
"""Water-vapor isobaric heat capacity [J/kg/K]."""
function cp_v end
"""Water-vapor isochoric heat capacity [J/kg/K]."""
function cv_v end
"""Liquid-water isobaric heat capacity [J/kg/K]."""
function cp_l end
"""Liquid-water isochoric heat capacity [J/kg/K]."""
function cv_l end
"""Ice isobaric heat capacity [J/kg/K]."""
function cp_i end
"""Ice isochoric heat capacity [J/kg/K]."""
function cv_i end
"""Ratio of molar masses `M_v/M_d`, equal to `R_d/R_v`."""
function molmass_ratio end
"""Reference pressure in the definition of potential temperature [Pa]."""
function p_ref_theta end
"""Reference temperature the latent heats are anchored at [K]."""
function T_0 end
"""Lowest temperature the saturation adjustment will return [K]."""
function T_min end
"""Freezing temperature [K]."""
function T_freeze end
"""Triple-point temperature [K]."""
function T_triple end
"""All-ice threshold temperature [K]."""
function T_icenuc end
"""Triple-point pressure [Pa]."""
function p_triple end
"""Latent heat of vaporization at `T_0` [J/kg]."""
function L_v0 end
"""Latent heat of sublimation at `T_0` [J/kg]."""
function L_s0 end
"""Reference specific internal energy of water vapor [J/kg]."""
function e_int_v0 end
"""Reference specific internal energy of ice [J/kg]."""
function e_int_i0 end
"""Latent heat at `T` [J/kg] from its reference value `LH_0` and the heat-capacity difference `Δcp`."""
function latent_heat_generic end
"""Latent heat of vaporization at `T` [J/kg]."""
function latent_heat_vapor end
"""Latent heat of sublimation at `T` [J/kg]."""
function latent_heat_sublim end
"""Latent heat of fusion at `T` [J/kg]."""
function latent_heat_fusion end
"""Saturation vapor pressure [Pa]."""
function saturation_vapor_pressure end
"""Saturation vapor pressure over liquid water [Pa]."""
function saturation_vapor_pressure_liq end
"""Saturation vapor pressure over ice [Pa]."""
function saturation_vapor_pressure_ice end
"""Saturation specific humidity from density."""
function q_vap_saturation end
"""Saturation specific humidity from pressure."""
function q_vap_saturation_from_pressure end
"""Specific humidity in excess of saturation."""
function saturation_excess end
"""Fraction of the condensate that is liquid."""
function liquid_fraction end
"""Equilibrium condensate partition `(q_liq, q_ice)`."""
function equilibrium_condensate end
"""Isobaric specific heat capacity of moist air [J/kg/K]."""
function cp_m end
"""Isochoric specific heat capacity of moist air [J/kg/K]."""
function cv_m end
"""Gas constant of moist air [J/kg/K]."""
function gas_constant_air end
"""Virtual temperature [K]."""
function virtual_temperature end
"""Moist air density [kg/m³]."""
function air_density end
"""Exner function."""
function exner end
"""Potential temperature of the moist air mixture [K]."""
function dry_pottemp end
"""Virtual potential temperature [K]."""
function virtual_pottemp end
"""Liquid-ice potential temperature [K]."""
function liquid_ice_pottemp end
"""Temperature [K] from the liquid-ice potential temperature and the condensate."""
function temperature_from_liquid_ice_pottemp end
"""Specific internal energy [J/kg]."""
function internal_energy end
"""Temperature [K] from the specific internal energy."""
function air_temperature end
"""Saturation adjustment from `(ρ, p, θ_li, q_tot)` → `(T, q_liq, q_ice)`."""
function saturation_adjust_ρθq end
"""Saturation adjustment from `(p, θ_li, q_tot)` → `(T, ρ, q_liq, q_ice)`."""
function saturation_adjust_pθq end
"""Volume mixing ratio of water vapor."""
function water_vapor_volume_mixing_ratio end

"""Supertype for the water phase a saturation quantity is taken over."""
abstract type AbstractPhase end
"""Water vapor."""
struct Vapor <: AbstractPhase end
"""Liquid water; saturation is taken over a plane liquid surface."""
struct Liquid <: AbstractPhase end
"""Ice; saturation is taken over a plane ice surface."""
struct Ice <: AbstractPhase end

# ============================================================================================ #
# Default backend constants, read from the parameter tables so a correction there cannot leave a
# stale copy here.
# ============================================================================================ #

@inline R_d(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_CONSTANTS.R_D)
@inline R_v(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.r_v)
@inline grav(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_CONSTANTS.G)
@inline cp_d(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cp_d)
@inline cv_d(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cv_d)
@inline cp_v(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cp_v)
@inline cv_v(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cv_v)
@inline cp_l(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cp_l)
@inline cv_l(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cv_l)
@inline cp_i(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cp_i)
@inline cv_i(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.cv_i)
@inline p_ref_theta(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.p00)
@inline T_0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.t_0)
@inline T_min(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.t_min)
@inline T_freeze(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.t_freeze)
@inline T_triple(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.t_triple)
@inline T_icenuc(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.t_icenuc)
@inline p_triple(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.p_triple)
@inline L_v0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.lh_v0)
@inline L_s0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.lh_s0)
@inline e_int_v0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.e_int_v0)
@inline e_int_i0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(SWIRL_LM_WATER.e_int_i0)

"""
    molmass_ratio(backend, FT)

`ε = M_v/M_d = R_d/R_v ≈ 0.62`. Computed from the gas constants so it cannot disagree with them.
Swirl-LM's `r_mix` is written with the reciprocal `R_v/R_d ≈ 1.61`; [`gas_constant_air`](@ref)
uses the equivalent form that needs neither.
"""
@inline molmass_ratio(b::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} =
    R_d(b, FT) / R_v(b, FT)

# --- Latent heats (`water.py:152-193`) --------------------------------------------------------- #

@inline latent_heat_generic(b::DefaultThermodynamicsBackend, T::FT, LH_0::FT, Δcp::FT) where {FT} =
    LH_0 + Δcp * (T - T_0(b, FT))

@inline latent_heat_vapor(b::DefaultThermodynamicsBackend, T::FT) where {FT} =
    latent_heat_generic(b, T, L_v0(b, FT), cp_v(b, FT) - cp_l(b, FT))

@inline latent_heat_sublim(b::DefaultThermodynamicsBackend, T::FT) where {FT} =
    latent_heat_generic(b, T, L_s0(b, FT), cp_v(b, FT) - cp_i(b, FT))

@inline latent_heat_fusion(b::DefaultThermodynamicsBackend, T::FT) where {FT} =
    latent_heat_generic(b, T, L_s0(b, FT) - L_v0(b, FT), cp_l(b, FT) - cp_i(b, FT))

# --- Saturation vapor pressure (`water.py:717-814`) -------------------------------------------- #

"""
    saturation_vapor_pressure(backend, T, LH_0, Δcp)

`p_triple (T/T_triple)^(Δcp/R_v) exp[(LH_0 − Δcp T_0)/R_v (1/T_triple − 1/T)]`, the
Clausius–Clapeyron relation integrated with a latent heat linear in temperature.
"""
@inline function saturation_vapor_pressure(
    b::DefaultThermodynamicsBackend, T::FT, LH_0::FT, Δcp::FT,
) where {FT}
    R_vap = R_v(b, FT)
    T_tr = T_triple(b, FT)
    return p_triple(b, FT) * (T / T_tr)^(Δcp / R_vap) *
           exp((LH_0 - Δcp * T_0(b, FT)) / R_vap * (one(FT) / T_tr - one(FT) / T))
end

@inline saturation_vapor_pressure_liq(b::DefaultThermodynamicsBackend, T::FT) where {FT} =
    saturation_vapor_pressure(b, T, L_v0(b, FT), cp_v(b, FT) - cp_l(b, FT))

@inline saturation_vapor_pressure_ice(b::DefaultThermodynamicsBackend, T::FT) where {FT} =
    saturation_vapor_pressure(b, T, L_s0(b, FT), cp_v(b, FT) - cp_i(b, FT))

@inline saturation_vapor_pressure(b::DefaultThermodynamicsBackend, T::FT, phase::Liquid) where {FT} = saturation_vapor_pressure_liq(b, T)
@inline saturation_vapor_pressure(b::DefaultThermodynamicsBackend, T::FT, phase::Ice) where {FT} = saturation_vapor_pressure_ice(b, T)

"""
    saturation_vapor_pressure(backend, T; λ)

Saturation vapor pressure over a liquid/ice mixture. The liquid fraction weights the reference
latent heat and the heat-capacity difference, which are then put through the single-phase
expression — a blend of the coefficients, not of two pressures.
"""
@inline function saturation_vapor_pressure(
    b::DefaultThermodynamicsBackend, T::FT; λ::FT = liquid_fraction(b, T),
) where {FT}
    LH_0 = λ * L_v0(b, FT) + (one(FT) - λ) * L_s0(b, FT)
    Δcp = λ * (cp_v(b, FT) - cp_l(b, FT)) + (one(FT) - λ) * (cp_v(b, FT) - cp_i(b, FT))
    return saturation_vapor_pressure(b, T, LH_0, Δcp)
end

# --- Saturation specific humidity (`water.py:816-895`) ----------------------------------------- #

"""
    q_vap_saturation(backend, T, ρ; λ)
    q_vap_saturation(backend, T, ρ, phase)

`q_v^* = p_sat / (ρ R_v T)`, the density form Swirl-LM's saturation adjustment uses.
"""
@inline q_vap_saturation(
    b::DefaultThermodynamicsBackend, T::FT, ρ::FT; λ::FT = liquid_fraction(b, T),
) where {FT} = saturation_vapor_pressure(b, T; λ) / (ρ * R_v(b, FT) * T)

@inline q_vap_saturation(
    b::DefaultThermodynamicsBackend, T::FT, ρ::FT, phase::AbstractPhase,
) where {FT} = saturation_vapor_pressure(b, T, phase) / (ρ * R_v(b, FT) * T)

"""
    q_vap_saturation_from_pressure(backend, T, p, q_tot; λ)

`(R_d/R_v)(1 − q_tot) p_sat / (p − p_sat)`, Swirl-LM's pressure form. It is not the reciprocal
of the density form: it carries the `(1 − q_tot)` factor and omits the `(1 − ε) p_sat` term that
the usual meteorological expression keeps.
"""
@inline function q_vap_saturation_from_pressure(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT; λ::FT = liquid_fraction(b, T),
) where {FT}
    p_v_sat = saturation_vapor_pressure(b, T; λ)
    return molmass_ratio(b, FT) * (one(FT) - q_tot) * p_v_sat / (p - p_v_sat)
end

@inline saturation_excess(
    b::DefaultThermodynamicsBackend, T::FT, ρ::FT, q_tot::FT; λ::FT = liquid_fraction(b, T),
) where {FT} = max(zero(FT), q_tot - q_vap_saturation(b, T, ρ; λ))

# --- Phase partition (`water.py:897-969`) ------------------------------------------------------ #

"""
    liquid_fraction(backend, T)
    liquid_fraction(backend, T, q_liq, q_c)

Fraction of the condensate that is liquid: 1 above freezing, 0 at or below the homogeneous ice
nucleation temperature, linear in temperature between. Given a condensate partition with
`q_c > 0`, the diagnosed `q_liq/q_c` is returned instead.
"""
@inline function liquid_fraction(b::DefaultThermodynamicsBackend, T::FT) where {FT}
    T_fr = T_freeze(b, FT)
    T_ice = T_icenuc(b, FT)
    T > T_fr && return one(FT)
    T <= T_ice && return zero(FT)
    return (T - T_ice) / (T_fr - T_ice)
end

@inline liquid_fraction(b::DefaultThermodynamicsBackend, T::FT, q_liq::FT, q_c::FT) where {FT} =
    q_c > zero(FT) ? q_liq / q_c : liquid_fraction(b, T)

"""
    equilibrium_condensate(backend, T, ρ, q_tot; λ) -> (; q_liq, q_ice)

Total water above saturation, partitioned by [`liquid_fraction`](@ref) at `T`.
"""
@inline function equilibrium_condensate(
    b::DefaultThermodynamicsBackend, T::FT, ρ::FT, q_tot::FT; λ::FT = liquid_fraction(b, T),
) where {FT}
    q_c = saturation_excess(b, T, ρ, q_tot; λ)
    return (; q_liq = λ * q_c, q_ice = (one(FT) - λ) * q_c)
end

# --- Mixture properties (`water.py:256-354`) --------------------------------------------------- #

"""
    cp_m(backend, q_tot, q_liq, q_ice)

`(1 − q_tot) cp_d + (q_tot − q_liq − q_ice) cp_v`. Swirl-LM's isobaric heat capacity of moist
air carries no `cp_l q_liq + cp_i q_ice` term, so it sees the condensate only through its
total: splitting a fixed `q_liq + q_ice` differently between the phases leaves it unchanged.
"""
@inline cp_m(
    b::DefaultThermodynamicsBackend, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} = (one(FT) - q_tot) * cp_d(b, FT) + (q_tot - q_liq - q_ice) * cp_v(b, FT)

@inline cv_m(
    b::DefaultThermodynamicsBackend, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    cv_d(b, FT) + (cv_v(b, FT) - cv_d(b, FT)) * q_tot +
    (cv_l(b, FT) - cv_v(b, FT)) * q_liq + (cv_i(b, FT) - cv_v(b, FT)) * q_ice

"""
    gas_constant_air(backend, q_tot, q_liq, q_ice)

`R_d(1 − q_tot) + R_v q_vap`, which is Swirl-LM's `R_d[1 + (ε−1) q_tot − ε q_c]` with
`ε = R_v/R_d` rearranged so no reciprocal molar-mass ratio appears.
"""
@inline gas_constant_air(
    b::DefaultThermodynamicsBackend, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} = R_d(b, FT) * (one(FT) - q_tot) + R_v(b, FT) * (q_tot - q_liq - q_ice)

@inline virtual_temperature(
    b::DefaultThermodynamicsBackend, T::FT, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} = T * gas_constant_air(b, q_tot, q_liq, q_ice) / R_d(b, FT)

@inline air_density(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} = p / (gas_constant_air(b, q_tot, q_liq, q_ice) * T)

# --- Potential temperatures (`water.py:1441-1634`) --------------------------------------------- #

"""
    exner(backend, p, q_tot, q_liq, q_ice)

`(p/p00)^(R_m/cp_m)`. `p` is the hydrostatic **reference** pressure, which is what Swirl-LM
passes here — not the local hydrodynamic pressure.
"""
@inline exner(
    b::DefaultThermodynamicsBackend, p::FT, q_tot::FT = zero(FT), q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    (p / p_ref_theta(b, FT))^(gas_constant_air(b, q_tot, q_liq, q_ice) / cp_m(b, q_tot, q_liq, q_ice))

@inline dry_pottemp(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT = zero(FT), q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} = T / exner(b, p, q_tot, q_liq, q_ice)

@inline virtual_pottemp(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT = zero(FT), q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    gas_constant_air(b, q_tot, q_liq, q_ice) / R_d(b, FT) * dry_pottemp(b, T, p, q_tot, q_liq, q_ice)

"""
    liquid_ice_pottemp(backend, T, p, q_tot, q_liq, q_ice)

`θ_li = (T − (L_v0 q_liq + L_s0 q_ice)/cp_m) / Π`, with the latent heats held at their reference
values rather than evaluated at `T`.
"""
@inline liquid_ice_pottemp(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT = zero(FT), q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    (T - (L_v0(b, FT) * q_liq + L_s0(b, FT) * q_ice) / cp_m(b, q_tot, q_liq, q_ice)) /
    exner(b, p, q_tot, q_liq, q_ice)

@inline temperature_from_liquid_ice_pottemp(
    b::DefaultThermodynamicsBackend, θ_li::FT, p::FT, q_tot::FT = zero(FT), q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    θ_li * exner(b, p, q_tot, q_liq, q_ice) +
    (L_v0(b, FT) * q_liq + L_s0(b, FT) * q_ice) / cp_m(b, q_tot, q_liq, q_ice)

# --- Internal energy (`water.py:675-715`, `:995-1032`) ----------------------------------------- #

@inline internal_energy(
    b::DefaultThermodynamicsBackend, T::FT, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    cv_m(b, q_tot, q_liq, q_ice) * (T - T_0(b, FT)) + (q_tot - q_liq) * e_int_v0(b, FT) -
    q_ice * (e_int_v0(b, FT) + e_int_i0(b, FT))

@inline air_temperature(
    b::DefaultThermodynamicsBackend, e_int::FT, q_tot::FT, q_liq::FT = zero(FT), q_ice::FT = zero(FT),
) where {FT} =
    T_0(b, FT) +
    (e_int - (q_tot - q_liq) * e_int_v0(b, FT) + q_ice * (e_int_v0(b, FT) + e_int_i0(b, FT))) /
    cv_m(b, q_tot, q_liq, q_ice)

"""
    water_vapor_volume_mixing_ratio(backend, q_tot, q_c)

`(R_v/R_d) q_vap / (1 − q_tot)`, the vapor volume mixing ratio the radiation reads.
"""
@inline water_vapor_volume_mixing_ratio(
    b::DefaultThermodynamicsBackend, q_tot::FT, q_c::FT = zero(FT),
) where {FT} = R_v(b, FT) / R_d(b, FT) * (q_tot - q_c) / (one(FT) - q_tot)

# --- Saturation adjustment (`water.py:1220-1361`, `numerics/root_finder.py:254-353`) ----------- #

"""
    _newton_secant(f, x0, maxiter, tol)

Swirl-LM's `root_finder.newton_method` without an analytic Jacobian: a Newton iteration whose
derivative is a central difference over `eps*|x|`, stopping once **either** `|f| ≤ tol` or
`|Δx| ≤ tol (1 + |x|)`.
"""
function _newton_secant(f::F, x0::FT, maxiter::Int, tol::FT) where {F, FT}
    # the perturbation of root_finder.py:290-291: the power of two nearest 10x the decimal resolution
    ϵ = exp2(ceil(log2(10 * FT(10)^(-floor(Int, log10(FT(2)^Base.significand_bits(FT)))))))
    x = x0
    fx = f(x)
    for _ in 1:maxiter
        abs(fx) <= tol && break
        dx = ϵ * abs(x)
        dx = iszero(dx) ? FT(1.0e-4) : dx          # root_finder.py:37 `_EPS`
        df = (f(x + dx / 2) - f(x - dx / 2)) / dx
        iszero(df) && break
        x_new = x - fx / df
        converged = abs(x_new - x) <= tol * (one(FT) + abs(x_new))
        x = x_new
        fx = f(x)
        converged && break
    end
    return x
end

"""
    saturation_adjust_ρθq(backend, ρ, p, θ_li, q_tot; maxiter, tol) -> (; T, q_liq, q_ice)

Temperature consistent with `(ρ, p, θ_li, q_tot)` at thermodynamic equilibrium, where `p` is the
hydrostatic reference pressure.

Three branches, as Swirl-LM has them: the unsaturated temperature is returned directly when
`q_tot` does not exceed saturation there and it sits above [`T_min`](@ref); the freezing
temperature is returned when `θ_li` is within `1e-6` of its value at freezing; otherwise the
secant iteration solves `θ_li(T) = θ_li`.

`maxiter` and `tol` default to Swirl-LM's own solver settings, which are loose (`1e-2`) because
they were chosen for throughput on TPU. Pass a smaller `tol` for a tighter root.
"""
function saturation_adjust_ρθq(
    b::DefaultThermodynamicsBackend, ρ::FT, p::FT, θ_li::FT, q_tot::FT;
    maxiter::Int = SWIRL_LM_WATER.max_temperature_iterations,
    tol::FT = FT(SWIRL_LM_WATER.temperature_tolerance),
) where {FT}
    θ_of(T) = liquid_ice_pottemp(b, T, p, q_tot, equilibrium_condensate(b, T, ρ, q_tot)...)

    T_unsat = temperature_from_liquid_ice_pottemp(b, θ_li, p, q_tot)
    T_1 = max(T_min(b, FT), T_unsat)

    T_fr = T_freeze(b, FT)
    if abs(θ_of(T_fr) - θ_li) < FT(1.0e-6)
        return (; T = T_fr, equilibrium_condensate(b, T_fr, ρ, q_tot)...)
    end

    T = if q_tot <= q_vap_saturation(b, T_1, ρ) && T_1 > T_min(b, FT)
        T_1
    else
        _newton_secant(T -> θ_of(T) - θ_li, T_1, maxiter, tol)
    end
    return (; T, equilibrium_condensate(b, T, ρ, q_tot)...)
end

"""
    saturation_adjust_pθq(backend, p, θ_li, q_tot; maxiter, tol, density_iterations) -> (; T, ρ, q_liq, q_ice)

Equilibrium state from the reference pressure, closing the density that
[`saturation_adjust_ρθq`](@ref) needs: `ρ ← p / (R_m T)` is iterated against the adjustment,
which is Swirl-LM's `saturation_density`.

Swirl-LM takes a single such iteration per timestep, warm-started from the previous step's
density. A standalone query has no previous step, so this iterates to convergence in `ρ` from
the unsaturated estimate instead; `density_iterations` bounds the loop.
"""
function saturation_adjust_pθq(
    b::DefaultThermodynamicsBackend, p::FT, θ_li::FT, q_tot::FT;
    maxiter::Int = SWIRL_LM_WATER.max_temperature_iterations,
    tol::FT = FT(SWIRL_LM_WATER.temperature_tolerance),
    density_iterations::Int = 20,
) where {FT}
    T = temperature_from_liquid_ice_pottemp(b, θ_li, p, q_tot)
    ρ = air_density(b, T, p, q_tot)
    local sat
    for _ in 1:density_iterations
        sat = saturation_adjust_ρθq(b, ρ, p, θ_li, q_tot; maxiter, tol)
        ρ_new = air_density(b, sat.T, p, q_tot, sat.q_liq, sat.q_ice)
        converged = abs(ρ_new - ρ) <= eps(FT) * 16 * abs(ρ_new)
        ρ = ρ_new
        converged && break
    end
    return (; sat.T, ρ, sat.q_liq, sat.q_ice)
end
