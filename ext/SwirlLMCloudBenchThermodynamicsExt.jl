"""
    SwirlLMCloudBenchThermodynamicsExt

Loads when `Thermodynamics` is available. A `ThermodynamicsParameters` set then serves directly as a
thermodynamics backend for every generic in `SwirlLMCloudBench`

Given the same constants, Thermodynamics.jl and Swirl-LM agree exactly on saturation vapor pressure (both integrate
Clausius–Clapeyron with a latent heat linear in temperature, anchored at the triple point), on the mixed-phase blend,
on the liquid-fraction ramp at `pow_icenuc = 1`, on `q_v^* = p_sat/(ρ R_v T)`, and on the moist gas constant. They
differ in one term: Thermodynamics.jl's `cp_m` keeps `cp_l q_liq + cp_i q_ice`, which Swirl-LM's drops. That
difference vanishes without condensate and propagates into `exner`, `θ_li` and the saturation adjustment when
condensate is present.
"""
module SwirlLMCloudBenchThermodynamicsExt

using SwirlLMCloudBench: SwirlLMCloudBench
using Thermodynamics: Thermodynamics as TD


# --- constants ---
@inline SwirlLMCloudBench.R_d(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.R_d(p))
@inline SwirlLMCloudBench.R_v(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.R_v(p))
@inline SwirlLMCloudBench.grav(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.grav(p))
@inline SwirlLMCloudBench.cp_d(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cp_d(p))
@inline SwirlLMCloudBench.cv_d(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cv_d(p))
@inline SwirlLMCloudBench.cp_v(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cp_v(p))
@inline SwirlLMCloudBench.cv_v(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cv_v(p))
@inline SwirlLMCloudBench.cp_l(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cp_l(p))
@inline SwirlLMCloudBench.cv_l(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cv_l(p))
@inline SwirlLMCloudBench.cp_i(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cp_i(p))
@inline SwirlLMCloudBench.cv_i(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.cv_i(p))
@inline SwirlLMCloudBench.p_ref_theta(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.p_ref_theta(p))
@inline SwirlLMCloudBench.T_0(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.T_0(p))
@inline SwirlLMCloudBench.T_min(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.T_min(p))
@inline SwirlLMCloudBench.T_freeze(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.T_freeze(p))
@inline SwirlLMCloudBench.T_triple(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.T_triple(p))
@inline SwirlLMCloudBench.T_icenuc(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.T_icenuc(p))
@inline SwirlLMCloudBench.p_triple(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.press_triple(p))
@inline SwirlLMCloudBench.L_v0(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.LH_v0(p))
@inline SwirlLMCloudBench.L_s0(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.LH_s0(p))
@inline SwirlLMCloudBench.e_int_v0(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.e_int_v0(p))
@inline SwirlLMCloudBench.e_int_i0(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.e_int_i0(p))

# Thermodynamics' own `molmass_ratio` is the reciprocal M_d/M_v ≈ 1.61; ε = R_d/R_v keeps the backend contract.
@inline SwirlLMCloudBench.molmass_ratio(p::TD.Parameters.ThermodynamicsParameters{FT}, ::Type{FT2} = FT) where {FT, FT2} = FT2(TD.Parameters.R_d(p) / TD.Parameters.R_v(p))

# --- latent heats ---
@inline SwirlLMCloudBench.latent_heat_generic(p::TD.Parameters.ThermodynamicsParameters, T, LH_0, Δcp) = TD.latent_heat_generic(p, T, LH_0, Δcp)
@inline SwirlLMCloudBench.latent_heat_vapor(p::TD.Parameters.ThermodynamicsParameters, T) = TD.latent_heat_vapor(p, T)
@inline SwirlLMCloudBench.latent_heat_sublim(p::TD.Parameters.ThermodynamicsParameters, T) = TD.latent_heat_sublim(p, T)
@inline SwirlLMCloudBench.latent_heat_fusion(p::TD.Parameters.ThermodynamicsParameters, T) = TD.latent_heat_fusion(p, T)

# --- saturation vapor pressure ---
@inline SwirlLMCloudBench.saturation_vapor_pressure(p::TD.Parameters.ThermodynamicsParameters, T, LH_0, Δcp) =
    TD.saturation_vapor_pressure_calc(p, T, LH_0, Δcp)
@inline SwirlLMCloudBench.saturation_vapor_pressure_liq(p::TD.Parameters.ThermodynamicsParameters, T) = TD.saturation_vapor_pressure(p, T, TD.Liquid())
@inline SwirlLMCloudBench.saturation_vapor_pressure_ice(p::TD.Parameters.ThermodynamicsParameters, T) = TD.saturation_vapor_pressure(p, T, TD.Ice())
@inline SwirlLMCloudBench.saturation_vapor_pressure(p::TD.Parameters.ThermodynamicsParameters, T, ::SwirlLMCloudBench.Liquid) = TD.saturation_vapor_pressure(p, T, TD.Liquid())
@inline SwirlLMCloudBench.saturation_vapor_pressure(p::TD.Parameters.ThermodynamicsParameters, T, ::SwirlLMCloudBench.Ice) = TD.saturation_vapor_pressure(p, T, TD.Ice())
@inline SwirlLMCloudBench.saturation_vapor_pressure(p::TD.Parameters.ThermodynamicsParameters, T; λ = SwirlLMCloudBench.liquid_fraction(p, T)) =
    TD.saturation_vapor_pressure_mixture(p, T, λ)

@inline SwirlLMCloudBench.liquid_fraction(p::TD.Parameters.ThermodynamicsParameters, T) = TD.liquid_fraction_ramp(p, T)
@inline SwirlLMCloudBench.liquid_fraction(p::TD.Parameters.ThermodynamicsParameters, T, q_liq, q_c) =
    q_c > zero(q_c) ? q_liq / q_c : SwirlLMCloudBench.liquid_fraction(p, T)

# --- saturation specific humidity ---
@inline SwirlLMCloudBench.q_vap_saturation(p::TD.Parameters.ThermodynamicsParameters, T, ρ; λ = SwirlLMCloudBench.liquid_fraction(p, T)) =
    TD.q_vap_from_p_vap(p, T, ρ, TD.saturation_vapor_pressure_mixture(p, T, λ))
@inline SwirlLMCloudBench.q_vap_saturation(p::TD.Parameters.ThermodynamicsParameters, T, ρ, ::SwirlLMCloudBench.Liquid) = TD.q_vap_saturation(p, T, ρ, TD.Liquid())
@inline SwirlLMCloudBench.q_vap_saturation(p::TD.Parameters.ThermodynamicsParameters, T, ρ, ::SwirlLMCloudBench.Ice) = TD.q_vap_saturation(p, T, ρ, TD.Ice())

# Swirl-LM's pressure form, which is not Thermodynamics' `q_vap_saturation_from_pressure`: it carries the
# (1 - q_tot) factor and omits the (1 - ε) p_sat term in the denominator.
@inline function SwirlLMCloudBench.q_vap_saturation_from_pressure(p::TD.Parameters.ThermodynamicsParameters, T, pres, q_tot; λ = SwirlLMCloudBench.liquid_fraction(p, T))
    p_v_sat = TD.saturation_vapor_pressure_mixture(p, T, λ)
    return SwirlLMCloudBench.molmass_ratio(p) * (1 - q_tot) * p_v_sat / (pres - p_v_sat)
end

@inline SwirlLMCloudBench.saturation_excess(p::TD.Parameters.ThermodynamicsParameters, T, ρ, q_tot; λ = SwirlLMCloudBench.liquid_fraction(p, T)) =
    max(zero(q_tot), q_tot - SwirlLMCloudBench.q_vap_saturation(p, T, ρ; λ))

@inline function SwirlLMCloudBench.equilibrium_condensate(p::TD.Parameters.ThermodynamicsParameters, T, ρ, q_tot; λ = SwirlLMCloudBench.liquid_fraction(p, T))
    q_c = SwirlLMCloudBench.saturation_excess(p, T, ρ, q_tot; λ)
    return (; q_liq = λ * q_c, q_ice = (one(λ) - λ) * q_c)
end

# --- mixture properties ---
@inline SwirlLMCloudBench.cp_m(p::TD.Parameters.ThermodynamicsParameters, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) = TD.cp_m(p, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.cv_m(p::TD.Parameters.ThermodynamicsParameters, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) = TD.cv_m(p, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.gas_constant_air(p::TD.Parameters.ThermodynamicsParameters, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) =
    TD.gas_constant_air(p, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.virtual_temperature(p::TD.Parameters.ThermodynamicsParameters, T, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) =
    TD.virtual_temperature(p, T, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.air_density(p::TD.Parameters.ThermodynamicsParameters, T, pres, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) =
    TD.air_density(p, T, pres, q_tot, q_liq, q_ice)

# --- potential temperatures ---
@inline SwirlLMCloudBench.exner(p::TD.Parameters.ThermodynamicsParameters, pres, q_tot = 0, q_liq = 0, q_ice = 0) =
    TD.exner_given_pressure(p, pres, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.dry_pottemp(p::TD.Parameters.ThermodynamicsParameters, T, pres, q_tot = 0, q_liq = 0, q_ice = 0) =
    TD.potential_temperature_given_pressure(p, T, pres, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.liquid_ice_pottemp(p::TD.Parameters.ThermodynamicsParameters, T, pres, q_tot = 0, q_liq = 0, q_ice = 0) =
    TD.liquid_ice_pottemp_given_pressure(p, T, pres, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.virtual_pottemp(p::TD.Parameters.ThermodynamicsParameters, T, pres, q_tot = 0, q_liq = 0, q_ice = 0) =
    TD.gas_constant_air(p, q_tot, q_liq, q_ice) / TD.Parameters.R_d(p) *
    TD.potential_temperature_given_pressure(p, T, pres, q_tot, q_liq, q_ice)
@inline SwirlLMCloudBench.temperature_from_liquid_ice_pottemp(p::TD.Parameters.ThermodynamicsParameters, θ_li, pres, q_tot = 0, q_liq = 0, q_ice = 0) =
    θ_li * TD.exner_given_pressure(p, pres, q_tot, q_liq, q_ice) +
    TD.humidity_weighted_latent_heat(p, q_liq, q_ice) / TD.cp_m(p, q_tot, q_liq, q_ice)

# --- internal energy ---
# Thermodynamics' own convention, so an `e_int` taken from a ClimaAtmos state round-trips here. It is anchored
# (1 - q_tot) R_d T_0 below Swirl-LM's, ~77 kJ/kg, so the two backends' `internal_energy` values are not
# comparable to each other; each inverts its own `air_temperature`, which is what callers rely on.
@inline SwirlLMCloudBench.internal_energy(p::TD.Parameters.ThermodynamicsParameters, T, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) =
    TD.internal_energy(p, T, q_tot, q_liq, q_ice)

@inline SwirlLMCloudBench.air_temperature(p::TD.Parameters.ThermodynamicsParameters, e_int, q_tot, q_liq = zero(q_tot), q_ice = zero(q_tot)) =
    TD.air_temperature(p, e_int, q_tot, q_liq, q_ice)

@inline SwirlLMCloudBench.water_vapor_volume_mixing_ratio(p::TD.Parameters.ThermodynamicsParameters, q_tot, q_c = zero(q_tot)) =
    TD.Parameters.R_v(p) / TD.Parameters.R_d(p) * (q_tot - q_c) / (one(q_tot) - q_tot)

# --- saturation adjustment ---
# The branch structure is Swirl-LM's; the thermodynamic functions underneath are Thermodynamics.jl's.
function SwirlLMCloudBench.saturation_adjust_ρθq(
    p::TD.Parameters.ThermodynamicsParameters{FT}, ρ, pres, θ_li, q_tot;
    maxiter::Int = 100, tol = FT(1.0e-6),
) where {FT}
    θ_of(T) = SwirlLMCloudBench.liquid_ice_pottemp(p, T, pres, q_tot, SwirlLMCloudBench.equilibrium_condensate(p, T, ρ, q_tot)...)
    T_unsat = SwirlLMCloudBench.temperature_from_liquid_ice_pottemp(p, θ_li, pres, q_tot)
    T_1 = max(SwirlLMCloudBench.T_min(p, FT), T_unsat)
    if q_tot <= SwirlLMCloudBench.q_vap_saturation(p, T_1, ρ) && T_1 > SwirlLMCloudBench.T_min(p, FT)
        return (; T = T_1, SwirlLMCloudBench.equilibrium_condensate(p, T_1, ρ, q_tot)...)
    end
    sol = TD.RS.find_zero(
        T -> θ_of(T) - θ_li,
        TD.RS.SecantMethod(T_1, T_1 + one(FT)),
        TD.RS.CompactSolution(),
        TD.RS.ResidualTolerance(FT(tol)),
        maxiter,
    )
    return (; T = sol.root, SwirlLMCloudBench.equilibrium_condensate(p, sol.root, ρ, q_tot)...)
end

function SwirlLMCloudBench.saturation_adjust_pθq(
    p::TD.Parameters.ThermodynamicsParameters{FT}, pres, θ_li, q_tot;
    maxiter::Int = 100, tol = FT(1.0e-6), density_iterations::Int = 20,
) where {FT}
    T = SwirlLMCloudBench.temperature_from_liquid_ice_pottemp(p, θ_li, pres, q_tot)
    ρ = SwirlLMCloudBench.air_density(p, T, pres, q_tot)
    local sat
    for _ in 1:density_iterations
        sat = SwirlLMCloudBench.saturation_adjust_ρθq(p, ρ, pres, θ_li, q_tot; maxiter, tol)
        ρ_new = SwirlLMCloudBench.air_density(p, sat.T, pres, q_tot, sat.q_liq, sat.q_ice)
        converged = abs(ρ_new - ρ) <= eps(FT) * 16 * abs(ρ_new)
        ρ = ρ_new
        converged && break
    end
    return (; sat.T, ρ, sat.q_liq, sat.q_ice)
end

end # module
