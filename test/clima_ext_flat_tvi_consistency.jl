# Checks that flat NetCDF written by `write_clima_tv_flat_forcing_netcdf_from_sounding!` round-trips the same
# `(z,time)` arrays as [`Simulation.cloudbench_sounding_zt_matrices`](@ref) (after Float64 promotion in the file).
#
# Also smoke-tests in-memory `ProvidedColumnTVForcing` from `build_provided_column_tv_forcing_from_cloudbench_sounding`
# at `t = 0` when `ClimaAtmos` defines `ProvidedColumnTVForcing` (needs a checkout that includes that API — see env below).
#
# Run:
#   julia --project=test/environments/clima -e 'import Pkg; Pkg.instantiate()'
#   julia --project=test/environments/clima test/clima_ext_flat_tvi_consistency.jl
#
# `test/environments/clima/Project.toml` **path-sources** sibling `../../../../../ClimaAtmos.jl`. If you instantiate only
# from General without that path override, `isdefined(ClimaAtmos, :ProvidedColumnTVForcing)` can be false because your
# resolved `ClimaAtmos` revision simply does not define that type yet — use a source tree that does.
#
# This is **not** part of the default `test/runtests.jl`.

using Test
using ClimaAtmos
using ClimaCore.Fields
using ClimaCore.Spaces
using ClimaCore.Utilities: half
using ClimaUtilities: TimeVaryingInputs as TVIs
using NCDatasets
using SwirlLMCloudBench: Simulation as S, SwirlLMCloudBench

function main()
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt) !== nothing
    @test isdefined(ClimaAtmos, :ProvidedColumnTVForcing)

    d = mktempdir()
    csv = joinpath(d, "s.csv")
    open(csv, "w") do io
        println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
        println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
        println(io, "1000,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
    end
    FT = Float64
    grid = ClimaAtmos.ColumnGrid(FT; z_elem = 10, z_max = 30000, z_stretch = false)
    sp = ClimaAtmos.get_spaces(grid)
    ce = sp.center_space
    su = Spaces.level(sp.face_space, half)
    snd = S.CloudBenchSounding(csv)
    nt = 4
    m = S.cloudbench_sounding_zt_matrices(snd, nt)

    nc = joinpath(d, "tv.nc")
    SwirlLMCloudBench.write_clima_tv_flat_forcing_netcdf_from_sounding!(nc, snd, nt)

    NCDataset(nc) do ds
        ta_nc = Array(ds["ta"])
        @test ta_nc ≈ FT.(m.temperature)
    end

    F = SwirlLMCloudBench.build_provided_column_tv_forcing_from_cloudbench_sounding(ce, su, snd, nt)
    ta_in = F.column_timevaryinginputs.ta
    dest = Fields.zeros(FT, ce)
    TVIs.evaluate!(dest, ta_in, FT(0))
    @info "ta TVI at t=0 extrema (in-memory ProvidedColumnTVForcing)" extrema(parent(dest))

    return nothing
end

main()
