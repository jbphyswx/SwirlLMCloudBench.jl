# Verifies SwirlLMCloudBenchClimaAtmosExt against the REGISTERED ClimaAtmos stack.
#
# Run with `test/environments/clima` environment.
#
# This is NOT part of the default `test/runtests.jl` (heavy ClimaAtmos dependency); CI runs it as a separate gated job.

using Test: Test
using ClimaAtmos: ClimaAtmos
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench

function write_test_sounding(dir)
    csv = joinpath(dir, "s.csv")
    open(csv, "w") do io
        println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
        #        z,    theta_li, T,    q_t,    u,  v,  w,     T_adv_src, q_t_adv_src, T,  p,       rho,   cld_frac
        println(io, "0,300,300,0.015,-7,-2,0.0,-1.9e-5,-1.8e-8,300,1.013e5,1.18,0.15")
        println(io, "1000,295,290,0.010,-6,-1,-0.01,-1.5e-5,-1.2e-8,290,9.0e4,1.0,0.2")
        println(io, "5000,270,260,0.003,2,1,-0.02,-1.0e-5,-0.8e-8,260,5.4e4,0.7,0.05")
        println(io, "20000,230,220,1e-5,10,0,0.0,0.0,0.0,220,5.5e3,0.087,0.0")
    end
    return csv
end

Test.@testset "SwirlLMCloudBenchClimaAtmosExt (registered ClimaAtmos $(SwirlLMCloudBench.climaatmos_pkg_version()))" begin
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt) !== nothing

    FT = Float64
    # everything lives inside the block: the sounding and the round-trip file are both
    # written here, and both are read further down
    mktempdir() do dir
        snd = S.CloudBenchSounding(write_test_sounding(dir); eltype = FT)

        # a synthetic sounding carries no SST/insolation, so they are stated here
        T_sfc, coszen, rsdt = FT(301.0), FT(0.5), FT(400.0)

        # --- in-memory forcing object ---
        cbf = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(
            snd; FT = FT, cos_zenith = coszen, toa_flux = rsdt,
        )
        Test.@test cbf.nudge
        cbf_nonudge = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchForcing(
            snd; FT = FT, cos_zenith = coszen, toa_flux = rsdt, nudge = false,
        )

        # --- minimal column state Y + params ---
        grid = ClimaAtmos.ColumnGrid(FT; z_elem = 30, z_max = 30000.0, z_stretch = false)
        sp = ClimaAtmos.get_spaces(grid)
        cspace = sp.center_space
        coords = ClimaAtmos.CC.Fields.coordinate_field(cspace)
        Y = (; c = map(_ -> (; ρ = FT(1)), coords))
        params = ClimaAtmos.ClimaAtmosParameters(FT)

        # --- in-memory cache: every field finite, including the insolation scalars ---
        cache = ClimaAtmos.external_forcing_cache(Y, cbf, params, nothing)
        for k in keys(cache)
            Test.@test all(isfinite, parent(cache[k]))
        end
        Test.@test all(==(coszen), parent(cache.cos_zenith))
        Test.@test all(==(rsdt), parent(cache.toa_flux))
        Test.@test any(>(0), parent(cache.ᶜinv_τ_scalar))      # nudging is on aloft

        # nudge=false zeroes the relaxation timescales
        cache_nn = ClimaAtmos.external_forcing_cache(Y, cbf_nonudge, params, nothing)
        Test.@test all(==(0), parent(cache_nn.ᶜinv_τ_scalar))
        Test.@test all(==(0), parent(cache_nn.ᶜinv_τ_wind))

        # --- the forcing round-trips through a file, in this package's own type and format ---
        fnc = joinpath(dir, "ClimaAtmosSwirlLMCloudBenchForcing.nc")
        SwirlLMCloudBench.write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf!(fnc, cbf)
        cbf_read = SwirlLMCloudBench.read_ClimaAtmosSwirlLMCloudBenchForcing(fnc; FT = FT)
        for name in fieldnames(typeof(cbf))
            Test.@test getfield(cbf_read, name) == getfield(cbf, name)
        end
        cache_rt = ClimaAtmos.external_forcing_cache(Y, cbf_read, params, nothing)
        for k in keys(cache)
            Test.@test parent(cache_rt[k]) == parent(cache[k])
        end

        # the tendency dispatches on this package's own type. That it did not was the
        # defect this file previously missed: a dummy `ExternalDrivenTVForcing` was used
        # for dispatch, and no method here could have applied.
        Test.@test hasmethod(
            ClimaAtmos.external_forcing_tendency!,
            Tuple{Any, Any, Any, Any, typeof(cbf)},
        )

        # --- setup: ICs + forcing in one object, ready for ClimaAtmos.AtmosSimulation ---
        setup = SwirlLMCloudBench.ClimaAtmosSwirlLMCloudBenchSetup(
            snd; FT = FT, surface_temperature = T_sfc, cos_zenith = coszen, toa_flux = rsdt,
        )
        Test.@test ClimaAtmos.Setups.external_forcing(setup, FT) isa typeof(cbf)
        sc = ClimaAtmos.Setups.surface_condition(setup, params)
        Test.@test sc.flux_scheme !== nothing && sc.temperature !== nothing
        # the surface temperature is the SST given, not the lowest air level
        Test.@test sc.temperature.f(nothing) == T_sfc
        # insolation is this package's own model, reading the case's values from the forcing cache
        ext = Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt)
        Test.@test ClimaAtmos.Setups.insolation_model(setup) isa
                   ext.ClimaAtmosSwirlLMCloudBenchInsolation

        Y = ClimaAtmos.Setups.initial_state(
            setup, params, ClimaAtmos.AtmosModel(), cspace, sp.face_space,
        )
        Test.@test all(isfinite, parent(Y.c))
        Test.@test all(isfinite, parent(Y.f))
        # the state carries the sounding, so the column spans the sounding's own range
        zc = vec(Array(parent(ClimaAtmos.CC.Fields.coordinate_field(cspace).z)))
        T_col = vec(Array(parent(ClimaAtmos.CC.Fields.level(Y.c.ρ, 1))))
        Test.@test length(T_col) == 1
        Test.@test minimum(zc) > 0 && maximum(zc) < 30000
        ρ = vec(Array(parent(Y.c.ρ)))
        Test.@test all(>(0), ρ)
        # air thins upwards, so the lowest cell is denser than the highest
        Test.@test first(ρ) > last(ρ)
    end
end
