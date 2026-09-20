using Test: Test
using SwirlLMCloudBench: SwirlLMCloudBench

# The default backend against properties of Swirl-LM's own formulas. Each assertion can fail for a
# reason: the parameter table is checked against the identities the proto values satisfy, and the
# functions against limits and round-trips that a wrong transcription would break.

const W = SwirlLMCloudBench.SWIRL_LM_WATER
const C = SwirlLMCloudBench.SWIRL_LM_CONSTANTS

Test.@testset "SWIRL_LM_WATER is internally consistent" begin
    # the reference internal energies are derived from the latent heats, so they pin them together;
    # e_int_v0 is stated to four significant figures, hence the 1e-4 tolerance
    Test.@test isapprox(W.e_int_v0, W.lh_v0 - W.r_v * W.t_0; rtol = 1e-4)
    Test.@test W.e_int_i0 ≈ W.lh_s0 - W.lh_v0
    # cp_d is derived, and is deliberately not SWIRL_LM_CONSTANTS.CP
    Test.@test W.cp_d == W.cv_d + C.R_D
    Test.@test W.cp_d != C.CP
    Test.@test W.t_icenuc < W.t_freeze < W.t_triple
end

Test.@testset "saturation vapor pressure" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    # at the triple point the power-law and exponential factors are both unity, for either phase
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure_liq(b, W.t_triple) ≈ W.p_triple rtol = 1e-14
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure_ice(b, W.t_triple) ≈ W.p_triple rtol = 1e-14
    # below freezing the liquid surface has the higher vapor pressure
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure_liq(b, 250.0) > SwirlLMCloudBench.saturation_vapor_pressure_ice(b, 250.0)
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure_liq(b, 300.0) > SwirlLMCloudBench.saturation_vapor_pressure_liq(b, 280.0)
    # the mixture is the single-phase value at either end of the ramp
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure(b, 300.0) ≈ SwirlLMCloudBench.saturation_vapor_pressure_liq(b, 300.0)
    Test.@test SwirlLMCloudBench.saturation_vapor_pressure(b, 200.0) ≈ SwirlLMCloudBench.saturation_vapor_pressure_ice(b, 200.0)
end

Test.@testset "liquid fraction ramp" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    Test.@test SwirlLMCloudBench.liquid_fraction(b, W.t_icenuc) == 0
    Test.@test SwirlLMCloudBench.liquid_fraction(b, W.t_freeze) == 1
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 200.0) == 0
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 320.0) == 1
    Test.@test SwirlLMCloudBench.liquid_fraction(b, (W.t_icenuc + W.t_freeze) / 2) ≈ 0.5
    # a diagnosed partition takes precedence over the temperature ramp
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 250.0, 3.0e-4, 4.0e-4) ≈ 0.75
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 250.0, 0.0, 0.0) == SwirlLMCloudBench.liquid_fraction(b, 250.0)
end

Test.@testset "mixture properties" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    Test.@test SwirlLMCloudBench.gas_constant_air(b, 0.0) ≈ C.R_D
    Test.@test SwirlLMCloudBench.cp_m(b, 0.0) ≈ W.cp_d
    Test.@test SwirlLMCloudBench.cv_m(b, 0.0) ≈ W.cv_d
    # Swirl-LM's cp_m has no cp_l*q_liq + cp_i*q_ice term, so a fixed condensate split differently
    # leaves it unchanged. This is the assertion that fires if it is ever "corrected" to the
    # textbook form, which would silently change theta_li and the saturation adjustment.
    Test.@test SwirlLMCloudBench.cp_m(b, 0.01, 0.003, 0.0) == SwirlLMCloudBench.cp_m(b, 0.01, 0.0, 0.003)
    # it does fall as vapour becomes condensate, through the (q_tot - q_liq - q_ice) term
    Test.@test SwirlLMCloudBench.cp_m(b, 0.01, 0.003, 0.0) < SwirlLMCloudBench.cp_m(b, 0.01, 0.0, 0.0)
    Test.@test SwirlLMCloudBench.virtual_temperature(b, 288.0, 0.012) > 288.0
    Test.@test SwirlLMCloudBench.air_density(b, 288.0, 1.0e5, 0.0) ≈ 1.0e5 / (C.R_D * 288.0)
end

Test.@testset "potential temperatures and round-trips" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    T, p, q = 288.0, 9.0e4, 0.012
    Test.@test SwirlLMCloudBench.exner(b, W.p00) == 1
    Test.@test SwirlLMCloudBench.dry_pottemp(b, T, W.p00) ≈ T
    # with no condensate theta_li is theta
    Test.@test SwirlLMCloudBench.liquid_ice_pottemp(b, T, p, q) ≈ SwirlLMCloudBench.dry_pottemp(b, T, p, q)
    Test.@test SwirlLMCloudBench.virtual_pottemp(b, T, p, q) > SwirlLMCloudBench.dry_pottemp(b, T, p, q)
    for (ql, qi) in ((0.0, 0.0), (1.0e-4, 0.0), (0.0, 5.0e-5), (2.0e-4, 1.0e-4))
        θ = SwirlLMCloudBench.liquid_ice_pottemp(b, T, p, q, ql, qi)
        Test.@test SwirlLMCloudBench.temperature_from_liquid_ice_pottemp(b, θ, p, q, ql, qi) ≈ T rtol = 1e-12
        e = SwirlLMCloudBench.internal_energy(b, T, q, ql, qi)
        Test.@test SwirlLMCloudBench.air_temperature(b, e, q, ql, qi) ≈ T rtol = 1e-12
    end
end

Test.@testset "saturation adjustment" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    # the rho form recovers the temperature the state was built at
    for (T, p, q) in ((288.0, 1.0e5, 0.002), (300.0, 1.0e5, 0.02), (260.0, 7.0e4, 0.004))
        ρ = SwirlLMCloudBench.air_density(b, T, p, q)
        cnd = SwirlLMCloudBench.equilibrium_condensate(b, T, ρ, q)
        θ = SwirlLMCloudBench.liquid_ice_pottemp(b, T, p, q, cnd.q_liq, cnd.q_ice)
        Test.@test SwirlLMCloudBench.saturation_adjust_ρθq(b, ρ, p, θ, q; tol = 1e-10).T ≈ T atol = 1e-4
    end
    # the p form has to satisfy both equations it claims to solve
    for (θ, p, q) in ((290.0, 1.0e5, 0.002), (295.0, 1.0e5, 0.02), (270.0, 7.0e4, 0.004))
        s = SwirlLMCloudBench.saturation_adjust_pθq(b, p, θ, q; tol = 1e-10)
        Test.@test s.ρ ≈ SwirlLMCloudBench.air_density(b, s.T, p, q, s.q_liq, s.q_ice) rtol = 1e-10
        Test.@test SwirlLMCloudBench.liquid_ice_pottemp(b, s.T, p, q, s.q_liq, s.q_ice) ≈ θ atol = 1e-6
        cnd = SwirlLMCloudBench.equilibrium_condensate(b, s.T, s.ρ, q)
        Test.@test cnd.q_liq ≈ s.q_liq atol = 1e-12
        Test.@test cnd.q_ice ≈ s.q_ice atol = 1e-12
    end
    # an unsaturated column condenses nothing
    let p = 1.0e5, q = 1.0e-4
        s = SwirlLMCloudBench.saturation_adjust_pθq(b, p, 300.0, q)
        Test.@test s.q_liq == 0 && s.q_ice == 0
    end
end
