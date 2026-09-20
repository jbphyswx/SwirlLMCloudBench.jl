using Test: Test
using SwirlLMCloudBench: SwirlLMCloudBench
using Thermodynamics: Thermodynamics as TD

# Backend conformance. Every backend the package ships must answer every generic the package
# declares, with a physically sane value, and must invert its own definitions.
#
# No numeric agreement between backends is asserted. Backends are free to use different
# Clausius-Clapeyron closures, or temperature-dependent rather than constant latent heats, so an
# equality here would be a test of Thermodynamics.jl rather than of this package, and would forbid
# adding a backend whose physics differs. Where the two do coincide, that is recorded in
# `docs/cloudbench_reference.md`, not asserted here.

const W = SwirlLMCloudBench.SWIRL_LM_WATER
const C = SwirlLMCloudBench.SWIRL_LM_CONSTANTS

# ClimaParams' defaults, stated here so the test needs no ClimaParams dependency.
function base_thermodynamics_parameters()
    vals = (;
        T_0 = 273.16, T_triple = 273.16, T_freeze = 273.15, T_icenuc = 233.0,
        T_min = 1.0, T_max = 1000.0, T_init_min = 150.0, T_surf_ref = 288.0, T_min_ref = 220.0,
        entropy_reference_temperature = 298.15, MSLP = 101325.0, p_ref_theta = 1.0e5,
        press_triple = 611.657, R_d = 287.0, R_v = 461.5, cp_d = 1004.5, cp_v = 1859.0,
        cp_l = 4181.0, cp_i = 2070.0, LH_v0 = 2500800.0, LH_s0 = 2834400.0,
        entropy_dry_air = 6864.8, entropy_water_vapor = 10513.6, grav = 9.81, pow_icenuc = 1.0,
        q_min = 1.0e-10,
    )
    fns = fieldnames(TD.Parameters.ThermodynamicsParameters)
    absent = filter(fn -> !haskey(vals, fn), fns)
    isempty(absent) || error("ThermodynamicsParameters gained fields this fixture does not set: $(absent)")
    return TD.Parameters.ThermodynamicsParameters{Float64}(; (fn => vals[fn] for fn in fns)...)
end

Test.@testset "Thermodynamics extension loads" begin
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchThermodynamicsExt) !== nothing
end


Test.@testset "backend conformance: $label" for (label, k) in (
    ("default", SwirlLMCloudBench.DefaultThermodynamicsBackend()),
)
    Test.@testset "constants" begin
        for f in (SwirlLMCloudBench.R_d, SwirlLMCloudBench.R_v, SwirlLMCloudBench.grav, SwirlLMCloudBench.cp_d, SwirlLMCloudBench.cv_d, SwirlLMCloudBench.cp_v, SwirlLMCloudBench.cv_v, SwirlLMCloudBench.cp_l, SwirlLMCloudBench.cv_l,
                  SwirlLMCloudBench.cp_i, SwirlLMCloudBench.cv_i, SwirlLMCloudBench.p_ref_theta, SwirlLMCloudBench.T_0, SwirlLMCloudBench.T_min, SwirlLMCloudBench.T_freeze, SwirlLMCloudBench.T_triple,
                  SwirlLMCloudBench.T_icenuc, SwirlLMCloudBench.p_triple, SwirlLMCloudBench.L_v0, SwirlLMCloudBench.L_s0, SwirlLMCloudBench.e_int_v0, SwirlLMCloudBench.e_int_i0)
            v = f(k)
            Test.@test isfinite(v) && v > 0
        end
        Test.@test SwirlLMCloudBench.R_v(k) > SwirlLMCloudBench.R_d(k)
        Test.@test 0 < SwirlLMCloudBench.molmass_ratio(k) < 1     # M_v/M_d, not Thermodynamics' reciprocal
        Test.@test SwirlLMCloudBench.R_d(k, Float32) isa Float32  # the 2-arg form the pipeline uses to fix precision
    end

    T, p, q = 288.0, 9.0e4, 0.012
    ρ = SwirlLMCloudBench.air_density(k, T, p, q)

    Test.@testset "saturation" begin
        Test.@test ρ > 0
        Test.@test SwirlLMCloudBench.saturation_vapor_pressure_liq(k, 260.0) > SwirlLMCloudBench.saturation_vapor_pressure_ice(k, 260.0)
        Test.@test SwirlLMCloudBench.saturation_vapor_pressure_liq(k, 300.0) > SwirlLMCloudBench.saturation_vapor_pressure_liq(k, 280.0)
        Test.@test 0 < SwirlLMCloudBench.q_vap_saturation(k, T, ρ) < 1
        Test.@test 0 < SwirlLMCloudBench.q_vap_saturation(k, T, ρ, SwirlLMCloudBench.Liquid()) < 1
        Test.@test 0 < SwirlLMCloudBench.q_vap_saturation_from_pressure(k, T, p, q) < 1
        Test.@test SwirlLMCloudBench.saturation_excess(k, T, ρ, q) >= 0
        cnd = SwirlLMCloudBench.equilibrium_condensate(k, T, ρ, q)
        Test.@test cnd.q_liq >= 0 && cnd.q_ice >= 0
        Test.@test cnd.q_liq + cnd.q_ice <= q
    end

    Test.@testset "liquid fraction" begin
        Test.@test SwirlLMCloudBench.liquid_fraction(k, SwirlLMCloudBench.T_freeze(k)) == 1
        Test.@test SwirlLMCloudBench.liquid_fraction(k, SwirlLMCloudBench.T_icenuc(k)) == 0
        Test.@test SwirlLMCloudBench.liquid_fraction(k, 250.0) > SwirlLMCloudBench.liquid_fraction(k, 240.0)
        Test.@test SwirlLMCloudBench.liquid_fraction(k, 250.0, 1.0e-4, 1.0e-4) == 1
    end

    Test.@testset "latent heats and mixture properties" begin
        Test.@test SwirlLMCloudBench.latent_heat_sublim(k, T) > SwirlLMCloudBench.latent_heat_vapor(k, T)
        Test.@test isfinite(SwirlLMCloudBench.latent_heat_fusion(k, T))
        Test.@test SwirlLMCloudBench.cp_m(k, q) > SwirlLMCloudBench.cv_m(k, q) > 0
        Test.@test SwirlLMCloudBench.gas_constant_air(k, 0.0) ≈ SwirlLMCloudBench.R_d(k)
        Test.@test SwirlLMCloudBench.gas_constant_air(k, q) > SwirlLMCloudBench.R_d(k)
        Test.@test SwirlLMCloudBench.virtual_temperature(k, T, q) > T
        Test.@test SwirlLMCloudBench.water_vapor_volume_mixing_ratio(k, q) > 0
    end

    Test.@testset "potential temperatures" begin
        Test.@test SwirlLMCloudBench.exner(k, p, q) < 1
        Test.@test SwirlLMCloudBench.dry_pottemp(k, T, p, q) > T
        Test.@test SwirlLMCloudBench.virtual_pottemp(k, T, p, q) > SwirlLMCloudBench.dry_pottemp(k, T, p, q)
        Test.@test SwirlLMCloudBench.liquid_ice_pottemp(k, T, p, q) ≈ SwirlLMCloudBench.dry_pottemp(k, T, p, q) rtol = 1e-12
    end

    Test.@testset "each backend inverts its own definitions" begin
        θ = SwirlLMCloudBench.liquid_ice_pottemp(k, T, p, q, 1.0e-4, 2.0e-5)
        Test.@test SwirlLMCloudBench.temperature_from_liquid_ice_pottemp(k, θ, p, q, 1.0e-4, 2.0e-5) ≈ T rtol = 1e-12
        # internal energy is anchored differently by each package, so only the round-trip is meaningful
        e = SwirlLMCloudBench.internal_energy(k, T, q, 1.0e-4, 2.0e-5)
        Test.@test SwirlLMCloudBench.air_temperature(k, e, q, 1.0e-4, 2.0e-5) ≈ T rtol = 1e-10
    end

    Test.@testset "saturation adjustment solves what it claims" begin
        for (θ_in, pp, qq) in ((290.0, 1.0e5, 0.002), (295.0, 1.0e5, 0.02), (270.0, 7.0e4, 0.004))
            s = SwirlLMCloudBench.saturation_adjust_pθq(k, pp, θ_in, qq; tol = 1e-10)
            Test.@test all(isfinite, values(s))
            Test.@test s.ρ ≈ SwirlLMCloudBench.air_density(k, s.T, pp, qq, s.q_liq, s.q_ice) rtol = 1e-9
            Test.@test SwirlLMCloudBench.liquid_ice_pottemp(k, s.T, pp, qq, s.q_liq, s.q_ice) ≈ θ_in atol = 1e-5
            # the two entry points agree with each other at the same density
            Test.@test SwirlLMCloudBench.saturation_adjust_ρθq(k, s.ρ, pp, θ_in, qq; tol = 1e-10).T ≈ s.T rtol = 1e-7
        end
    end
end
