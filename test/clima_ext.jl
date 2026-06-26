# Verifies SwirlLMCloudBenchClimaAtmosExt against the REGISTERED ClimaAtmos stack.
#
# Run:
#   julia --project=test/environments/clima -e 'import Pkg; Pkg.instantiate()'
#   julia --project=test/environments/clima test/clima_ext.jl
#
# This is NOT part of the default `test/runtests.jl` (heavy ClimaAtmos dependency); CI runs it as a separate gated job.

using Test: @test, @testset
using ClimaAtmos: ClimaAtmos
using ClimaCore: Fields, Spaces
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

@testset "SwirlLMCloudBenchClimaAtmosExt (registered ClimaAtmos $(SwirlLMCloudBench.climaatmos_pkg_version()))" begin
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt) !== nothing

    FT = Float64
    d = mktempdir()
    snd = S.CloudBenchSounding(write_test_sounding(d); eltype = FT)

    # --- in-memory forcing object ---
    cbf = SwirlLMCloudBench.cloudbench_forcing(snd; FT = FT)
    @test cbf.nudge
    cbf_nonudge = SwirlLMCloudBench.cloudbench_forcing(snd; FT = FT, nudge = false)

    # --- minimal column state Y + params ---
    grid = ClimaAtmos.ColumnGrid(FT; z_elem = 30, z_max = 30000.0, z_stretch = false)
    sp = ClimaAtmos.get_spaces(grid)
    cspace = sp.center_space
    coords = Fields.coordinate_field(cspace)
    Y = (; c = map(_ -> (; ρ = FT(1)), coords))
    params = ClimaAtmos.ClimaAtmosParameters(FT)

    # --- in-memory cache: all fields finite; eddy fluc is exactly zero (CloudBench has no Shen decomposition) ---
    cache = ClimaAtmos.external_forcing_cache(Y, cbf, params, nothing)
    for k in keys(cache)
        k in (:toa_flux, :cos_zenith) && continue   # NaN by default unless set
        @test all(isfinite, parent(cache[k]))
    end
    @test all(==(0), parent(cache.ᶜdTdt_fluc))
    @test all(==(0), parent(cache.ᶜdqtdt_fluc))
    @test all(>=(0), parent(cache.ᶜinv_τ_scalar))
    @test any(>(0), parent(cache.ᶜinv_τ_scalar))      # nudging is on aloft

    # nudge=false zeroes the relaxation timescales
    cache_nn = ClimaAtmos.external_forcing_cache(Y, cbf_nonudge, params, nothing)
    @test all(==(0), parent(cache_nn.ᶜinv_τ_scalar))
    @test all(==(0), parent(cache_nn.ᶜinv_τ_wind))

    # --- file path: write GCMForcing-schema NetCDF, read via stock ClimaAtmos.GCMForcing ---
    nc = joinpath(d, "gcm.nc")
    SwirlLMCloudBench.write_clima_gcm_forcing_sounding_netcdf!(nc, snd, "site_test"; rsdt = 400.0, coszen = 0.5)
    @test isfile(nc)
    gcmf = ClimaAtmos.GCMForcing{FT}(nc, "site_test")
    cache_file = ClimaAtmos.external_forcing_cache(Y, gcmf, params, nothing)
    # The directly-mapped fields agree between the in-memory and file (stock GCMForcing) paths to roundoff.
    for k in (
        :ᶜdTdt_hadv,
        :ᶜdqtdt_hadv,
        :ᶜT_nudge,
        :ᶜqt_nudge,
        :ᶜu_nudge,
        :ᶜv_nudge,
        :ᶜinv_τ_wind,
        :ᶜinv_τ_scalar,
    )
        @test parent(cache[k]) ≈ parent(cache_file[k]) rtol = 1e-6
    end
    # Subsidence: the in-memory path uses `w` directly (exact); the file path reconstructs w = -wap·α/g via GCMForcing's
    # hydrostatic relation, and the package builds `wap = -ρgw` with g = 9.80665 while ClimaAtmos's `grav` is 9.81 — so
    # the file path recovers w·(9.80665/9.81), a ~3e-4 difference. (Use the in-memory path for the exact subsidence.)
    @test parent(cache.ᶜls_subsidence) ≈ parent(cache_file.ᶜls_subsidence) rtol = 1e-3
    # (The eddy `fluc` fields also intentionally differ: in-memory is 0; stock GCMForcing reconstructs a vertical-eddy
    #  term from the zero `tntva`/`tnhusva`. Use the in-memory path for faithful CloudBench forcing.)

    # --- setup: ICs + forcing in one object, ready for ClimaAtmos.AtmosSimulation ---
    setup = SwirlLMCloudBench.cloudbench_setup(snd; FT = FT)
    @test ClimaAtmos.Setups.external_forcing(setup, FT) isa typeof(cbf)
    sc = ClimaAtmos.Setups.surface_condition(setup, params)
    @test sc.flux_scheme !== nothing && sc.temperature !== nothing
end
