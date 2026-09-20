using Test: Test
using InlineStrings: InlineStrings
using SwirlLMCloudBench:
    CaseDirs,
    Catalog,
    Config,
    Paths,
    Simulation as S,
    SwirlLMCloudBench

# Run Aqua first, on the pristine package (before the extension-triggering `using`s below load weakdeps).
include("test_aqua.jl")

# The default thermodynamics backend needs no weak dependency, so it runs here; the backend
# conformance file loads Thermodynamics and runs at the end with the other extension blocks.
include("unit_thermodynamics.jl")

Test.@testset "Catalog" begin
    Test.@test length(Catalog.CLOUDBENCH_CASE_INDICES) == 500
    Test.@test first(Catalog.CLOUDBENCH_CASE_INDICES) == 0
    Test.@test last(Catalog.CLOUDBENCH_CASE_INDICES) == 499
    Test.@test Catalog.CLOUDBENCH_MONTHS == (1, 4, 7, 10)
    Test.@test Catalog.n_cases() == 500
    Test.@test Set(Catalog.experiment_names()) == Set(collect(Catalog.EXPERIMENTS))
    Test.@test Catalog.parse_experiment("amip") === :amip
    Test.@test Catalog.parse_experiment(:amip_p4k) === :amip_p4k
    Test.@test_throws ArgumentError Catalog.parse_experiment("nope")
    Test.@test Catalog.valid_case_index(0) && Catalog.valid_case_index(499)
    Test.@test !Catalog.valid_case_index(-1) && !Catalog.valid_case_index(500)
    Test.@test Catalog.valid_month(1) && !Catalog.valid_month(2)
    Test.@test Catalog.gcs_path_segment(:amip) == "amip"
    Test.@test Catalog.gcs_path_segment(:amip_p4k) == "amip-p4k"
    Test.@test Catalog.gcs_path_segment("amip_p4k") == "amip-p4k"
    Test.@test Catalog.gcs_path_segment(Catalog.amip) == "amip"
    Test.@test Catalog.gcs_path_segment(Catalog.amip_p4k) == "amip-p4k"
    Test.@test Symbol(Catalog.amip_p4k) === :amip_p4k
    Test.@test Catalog.CloudBenchExperiment(:amip_4xco2) === Catalog.amip_4xco2
    Test.@test Catalog.CloudBenchExperiment("amip-p4k") === Catalog.amip_p4k
end

Test.@testset "Paths" begin
    root = Paths.package_root()
    Test.@test isdir(root)
    Test.@test isfile(joinpath(root, "Project.toml"))
    dr = Paths.default_data_root()
    Test.@test occursin("data", dr)
    cr = Paths.default_cache_root()
    Test.@test occursin("scratch", cr)
end

Test.@testset "Config" begin
    withenv(
        "SWIRL_LM_CLOUDBENCH_DATA_ROOT" => "",
        "SWIRL_LM_CLOUDBENCH_CACHE_ROOT" => "",
        "SWIRL_LM_CLOUDBENCH_RAW_ROOT" => "",
    ) do
        Test.@test Config.data_root() == Paths.default_data_root()
        Test.@test Config.cache_root() == Paths.default_cache_root()
    end
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_DATA_ROOT" => d) do
            Test.@test Config.data_root() == normpath(d)
        end
    end
    Test.@test Config.parse_bool_env("__SWIRL_LM_TEST_BOOL_XX__", false) == false
    withenv("__SWIRL_LM_TEST_BOOL_XX__" => "true") do
        Test.@test Config.parse_bool_env("__SWIRL_LM_TEST_BOOL_XX__", false) == true
    end
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_RAW_ROOT" => d) do
            Test.@test Config.raw_download_root() == normpath(d)
        end
    end
end

Test.@testset "CaseDirs.resolved_case_dir (canonical bucket layout)" begin
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_DATA_ROOT" => d) do
            p = CaseDirs.resolved_case_dir(10, 7, :amip)
            Test.@test p == joinpath(d, "10", "7", "amip")
            # consistent with the download / bucket layout
            Test.@test p == S.local_simulation_dir(d, S.CloudBenchInstance(10, 7, :amip))
        end
        Test.@test CaseDirs.resolved_case_dir(0, 4, :amip_p4k; root = d) == joinpath(d, "0", "4", "amip-p4k")
    end
    Test.@test_throws ArgumentError CaseDirs.resolved_case_dir(500, 7, :amip)
    Test.@test_throws ArgumentError CaseDirs.resolved_case_dir(0, 2, :amip)
    Test.@test_throws ArgumentError CaseDirs.resolved_case_dir(0, 7, :nope)
end

Test.@testset "CloudBenchSimulation and Simulation URLs" begin
    sl = S.CloudBenchSimulation(0, 1, :amip)
    Test.@test sl.site_id == 0 && sl.month == 1 && sl.experiment === Catalog.amip
    Test.@test isbitstype(S.CloudBenchInstance)
    sl2 = S.CloudBenchSimulation(Dict("site_id" => 7, "month" => 4, "experiment" => "amip"))
    Test.@test sl2.site_id == 7 && sl2.month == 4
    Test.@test_throws ArgumentError S.CloudBenchSimulation(Dict{String,Any}())
    u = S.cloudbench_sounding_url(sl)
    Test.@test occursin("storage.googleapis.com/cloudbench-simulation-output", u)
    Test.@test occursin("/0/1/amip/sounding.csv", u)
    u3 = S.cloudbench_sounding_url(0, 1, :amip)
    Test.@test u == u3
    z = S.cloudbench_zarr_url(0, 4, :amip_p4k)
    Test.@test occursin("/0/4/amip-p4k/data.zarr", z)
    Test.@test S.cloudbench_zarr_url(S.CloudBenchSimulation(0, 4, :amip_p4k)) == z
    purl = S.cloudbench_parameters_url(0, 1, :amip)
    Test.@test occursin("/0/1/amip/parameters.json", purl)
end

Test.@testset "local paths (bucket layout)" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    root = "/tmp/cloudbench_mirror"
    d = S.local_simulation_dir(root, sim)
    Test.@test d == joinpath(root, "0", "1", "amip")
    Test.@test S.sounding_path(sim, root) == joinpath(d, "sounding.csv")
    Test.@test S.parameters_path(sim, root) == joinpath(d, "parameters.json")
    Test.@test S.zarr_local_path(sim, root) == joinpath(d, "data.zarr")
    sim2 = S.CloudBenchSimulation(0, 4, :amip_p4k)
    Test.@test S.local_simulation_dir(root, sim2) == joinpath(root, "0", "4", "amip-p4k")
end

Test.@testset "CloudBenchParameters JSON" begin
    js = """
    {"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
    "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
    "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt"}
    """
    cp = S.parse_cloudbench_parameters(js)
    Test.@test cp isa S.CloudBenchParameters{Float32,InlineStrings.String127}   # isbits default
    Test.@test cp isa S.CloudBenchParametersDefault
    Test.@test cp.experiment == "amip" && cp.month == 1
    Test.@test cp.latitude ≈ 16.5f0 && cp.longitude ≈ -141.875f0
    # heap String storage available as an opt-in (for hypothetical longer paths)
    cp_str = S.parse_cloudbench_parameters(js; string_type = String)
    Test.@test cp_str isa S.CloudBenchParameters{Float32,String}
    Test.@test cp_str.experiment == "amip"
    mktempdir() do dir
        p = joinpath(dir, "p.json")
        write(p, js)
        cp2 = S.read_cloudbench_parameters(p)
        Test.@test cp2.sounding_path == "/x/sounding.csv"
    end
    js_extra = """
    {"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
    "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
    "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt","unexpected":1}
    """
    Test.@test_throws ArgumentError S.parse_cloudbench_parameters(js_extra)
    # strict=false ignores unknown keys (forward-compatible)
    Test.@test S.parse_cloudbench_parameters(js_extra; strict = false) isa S.CloudBenchParametersDefault
end

Test.@testset "open_zarr_local missing store" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    mktempdir() do root
        Test.@test_throws ArgumentError S.open_zarr_local(sim, root)
    end
end

Test.@testset "download_cloudbench_raw! zarr=false only" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    Test.@test_throws ArgumentError S.download_cloudbench_raw!(sim; zarr = true)
end

Test.@testset "load_cloudbench_simulation local_mirror=false" begin
    js = """
    {"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
    "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
    "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt"}
    """
    inst = S.CloudBenchInstance(0, 1, :amip)
    mktempdir() do root
        d = S.local_simulation_dir(root, inst)
        mkpath(d)
        write(S.parameters_path(inst, root), js)
        open(joinpath(d, "sounding.csv"), "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
            println(io, "100,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
        end
        r = S.load_cloudbench_simulation(inst; root = root, download = false, local_mirror = false)
        Test.@test r isa S.CloudBenchSimulationRemoteLoaded
        Test.@test r.metadata.parameters.experiment == "amip"
        Test.@test length(r.metadata.sounding.z) == 2
        Test.@test r.output isa S.RemoteCloudBenchZarrOutput
    end
end

if get(ENV, "CLOUDBENCH_NETWORK_TEST", "") == "1"
    Test.@testset "download_cloudbench_raw! (network)" begin
        mktempdir() do root
            sim = S.CloudBenchSimulation(0, 1, :amip)
            dir = S.download_cloudbench_raw!(sim; root = root)
            Test.@test dir == S.local_simulation_dir(root, sim)
            Test.@test isfile(S.sounding_path(sim, root))
            Test.@test isfile(S.parameters_path(sim, root))
            inst = S.CloudBenchInstance(0, 1, :amip)
            bundle = S.load_cloudbench_simulation(inst; root = root, download = false)
            Test.@test S.cloudbench_instance(bundle) == inst
            Test.@test bundle isa S.CloudBenchSimulationLoaded
            Test.@test bundle.metadata.parameters.experiment == "amip"
            Test.@test bundle.output isa S.LocalCloudBenchMirrorOutput
            Test.@test bundle.output.root == root
        end
    end

    Test.@testset "bundled soundings artifact (network)" begin
        inst = S.CloudBenchInstance(0, 1, :amip)
        d = S.bundled_soundings_dir()                       # downloads the ~10 MB artifact once
        Test.@test isdir(d)
        Test.@test isfile(S.bundled_sounding_path(inst))
        Test.@test isfile(S.bundled_parameters_path(inst))
        snd = S.bundled_sounding(inst)
        Test.@test snd isa S.CloudBenchSounding && length(snd.z) >= 2
    end

    Test.@testset "statistics: case-keyed reads over HTTPS byte ranges (network)" begin
        inst = S.CloudBenchInstance(0, 1, :amip)
        S.open_cloudbench_statistics_remote() do ds
            idx = S.cloudbench_statistics_indices(ds, inst)
            Test.@test idx.site == 1 && idx.month == 1 && idx.experiment >= 1
            # a simulation handle resolves to the same case as its instance
            Test.@test S.cloudbench_statistics_indices(ds, S.CloudBenchSimulation(0, 1, :amip)) == idx

            prof = S.cloudbench_statistics_profile(ds, inst, "T")
            Test.@test length(prof) == S.CLOUDBENCH_STATISTICS_NZ
            Test.@test all(x -> ismissing(x) || 100 < x < 400, prof)

            cc = S.cloudbench_statistics_scalar(ds, inst, "cloud_cover")
            Test.@test ismissing(cc) || 0 <= cc <= 1
            # diagnostics that exist here and in neither data.zarr nor the upstream variable table
            for name in ("cloud_feedback_lw", "cloud_feedback_sw", "lts", "eis", "subsidence_4km")
                v = S.cloudbench_statistics_scalar(ds, inst, name)
                Test.@test ismissing(v) || isfinite(v)
            end

            # a different case is a different read, so the indexing is not returning a fixed slice
            other = S.CloudBenchInstance(7, 7, :amip_p4k)
            Test.@test S.cloudbench_statistics_indices(ds, other) != idx
            Test.@test S.cloudbench_statistics_profile(ds, other, "T") != prof

            # asking for the wrong rank is refused rather than silently mis-indexed
            Test.@test_throws ArgumentError S.cloudbench_statistics_profile(ds, inst, "cloud_cover")
            Test.@test_throws ArgumentError S.cloudbench_statistics_scalar(ds, inst, "T")
        end
    end
end

Test.@testset "q_c split (Swirl-LM liquid fraction ramp)" begin
    b = SwirlLMCloudBench.DefaultThermodynamicsBackend()
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 233.0) == 0.0
    Test.@test SwirlLMCloudBench.liquid_fraction(b, 273.15) == 1.0
    q_l, q_i = SwirlLMCloudBench.split_q_c(0.1, 253.15)
    Test.@test q_l + q_i ≈ 0.1
    # the ramp is linear between the two endpoints, so the midpoint is half liquid
    Test.@test SwirlLMCloudBench.liquid_fraction(
        b,
        (SwirlLMCloudBench.T_icenuc(b) + SwirlLMCloudBench.T_freeze(b)) / 2,
    ) ≈ 0.5
end

Test.@testset "CloudBenchSounding and write_sounding_netcdf!" begin
    using NCDatasets: NCDatasets
    Test.@test S.CLOUDBENCH_SOUNDING_CSV_HEADER ==
          "z,theta_li,temperature,q_t,u,v,w,T_adv_src,q_t_adv_src,T,p,rho,cld_frac"
    mktempdir() do dir
        csv = joinpath(dir, "sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
            println(io, "100,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
        end
        s = S.CloudBenchSounding(csv)
        Test.@test s isa S.CloudBenchSounding{Float32,Vector{Float32}}
        Test.@test length(s.z) == 2
        Test.@test s.T == s.T_column
        Test.@test_throws DimensionMismatch S.CloudBenchSounding{Float32,Vector{Float32}}(
            [0.0f0],
            [1.0f0],
            [1.0f0],
            [0.01f0],
            [0.0f0],
            [0.0f0],
            [0.0f0],
            [0.0f0],
            [0.0f0],
            [1.0f0],
            [100_000.0f0],
            [1.0f0, 2.0f0],
            [0.0f0],
        )
        nc = joinpath(dir, "out.nc")
        S.write_sounding_netcdf!(nc, s, "site_test")
        Test.@test isfile(nc)
        NCDatasets.NCDataset(nc) do ds
            g = ds.group["site_test"]
            for name in (
                "z",
                "theta_li",
                "temperature",
                "q_t",
                "u",
                "v",
                "w",
                "T_adv_src",
                "q_t_adv_src",
                "T",
                "p",
                "rho",
                "cld_frac",
            )
                Test.@test haskey(g, name)
                Test.@test size(g[name]) == (2,)
            end
        end
        nc2 = joinpath(dir, "out2.nc")
        S.write_sounding_netcdf!(nc2, csv, "site2")
        Test.@test isfile(nc2)
    end
end

Test.@testset "CloudBenchSounding parse errors and cloudbench_sounding_zt_matrices" begin
    mktempdir() do dir
        csv = joinpath(dir, "rich_sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,300,280,0.01,1,2,0.1,1e-5,1e-8,280,1e5,1.2,0.3")
            println(io, "100,290,270,0.008,1,2,-0.05,2e-5,2e-8,270,9e4,1.0,0.2")
        end
        s = S.CloudBenchSounding(csv)
        Test.@test occursin("vertical level", sprint(show, s))
        nt = S.read_cloudbench_sounding_columns(csv, Float32)
        Test.@test nt.T_column == s.T_column
        m = S.cloudbench_sounding_zt_matrices(s, 4)
        Test.@test m.w[1, 1] == 0.1f0 && m.w[1, 3] == 0.1f0
        Test.@test m.temperature_horizontal_advective_tendency[1, 1] ≈ 1.0f-5 + 0.1f0 * (-0.1f0)
        Test.@test m.temperature_horizontal_advective_tendency[2, 2] ≈ 2.0f-5 + (-0.05f0) * (-0.1f0)
        Test.@test m.q_t_horizontal_advective_tendency[1, 1] ≈ 1.0f-8 + 0.1f0 * (-2.0f-5)
        Test.@test m.q_t_horizontal_advective_tendency[2, 2] ≈ 2.0f-8 + (-0.05f0) * (-2.0f-5)
        Tadv = S._profile_replicated(s.T_adv_src, length(s.z), 4)
        Qadv = S._profile_replicated(s.q_t_adv_src, length(s.z), 4)
        Test.@test m.temperature_horizontal_advective_tendency ≈ Tadv .+ m.temperature_vertical_advection
        Test.@test m.q_t_horizontal_advective_tendency ≈ Qadv .+ m.q_t_vertical_advection
        Test.@test m.vertical_pressure_velocity[1, 1] ≈
              -1.2f0 * Float32(SwirlLMCloudBench.SWIRL_LM_CONSTANTS.G) * 0.1f0
    end
    mktempdir() do dir
        bad = joinpath(dir, "bad.csv")
        open(bad, "w") do io
            println(io, "z,temperature,q_t,u,v,rho")
            println(io, "0,280,0.01,1,2,1.2")
            println(io, "100,270,0.008,1,2,1.0")
        end
        Test.@test_throws ErrorException S.CloudBenchSounding(bad)
    end
end

Test.@testset "value semantics (==/hash)" begin
    mktempdir() do dir
        csv = joinpath(dir, "sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
            println(io, "100,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
        end
        s1 = S.CloudBenchSounding(csv)
        s2 = S.CloudBenchSounding(csv)   # independently parsed: equal content, distinct Vectors
        Test.@test s1 == s2                    # was broken before (fell back to === on Vector fields)
        Test.@test hash(s1) == hash(s2)
        Test.@test length(Set([s1, s2])) == 1
        js = """{"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
        "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
        "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt"}"""
        inst = S.CloudBenchInstance(0, 1, :amip)
        d = S.local_simulation_dir(dir, inst)
        mkpath(d)
        write(S.parameters_path(inst, dir), js)
        cp(csv, S.sounding_path(inst, dir))
        a = S.load_cloudbench_simulation(inst; root = dir, download = false)
        b = S.load_cloudbench_simulation(inst; root = dir, download = false)
        Test.@test a isa S.CloudBenchSimulationLoaded
        Test.@test a == b                      # full metadata chain incl. parsed sounding
        Test.@test hash(a) == hash(b)
    end
    i1 = S.CloudBenchInstance(3, 4, :amip_p4k)
    i2 = S.CloudBenchInstance(3, 4, :amip_p4k)
    Test.@test i1 == i2 && hash(i1) == hash(i2)
    Test.@test haskey(Dict(i1 => :x), i2)
end

Test.@testset "split_q_c arrays + promotion" begin
    # mixed scalar types promote
    ql, qi = SwirlLMCloudBench.split_q_c(0.1f0, 253.15)
    Test.@test ql + qi ≈ 0.1f0
    # array form returns two arrays (the documented data.zarr use)
    q_c = [0.1, 0.2, 0.0]
    T = [253.15, 233.0, 300.0]
    q_liq, q_ice = SwirlLMCloudBench.split_q_c(q_c, T)
    Test.@test q_liq isa AbstractVector && q_ice isa AbstractVector
    Test.@test q_liq .+ q_ice ≈ q_c
    Test.@test q_ice[2] ≈ 0.2          # all ice at 233 K
    Test.@test_throws DimensionMismatch SwirlLMCloudBench.split_q_c([0.1, 0.2], [253.15])
end

Test.@testset "CloudBenchSelection (lazy)" begin
    sel = S.CloudBenchSelection((0, 1), (1,), (:amip, :amip_p4k))
    Test.@test length(sel) == 4
    sims = collect(sel)
    Test.@test length(sims) == 4
    Test.@test sims[1] == S.CloudBenchSimulation(0, 1, :amip)
    g = S.each_simulation(sel)
    Test.@test collect(g) == sims
    full = S.CloudBenchSelection()
    Test.@test length(full) == length(Catalog.CLOUDBENCH_CASE_INDICES) * length(Catalog.CLOUDBENCH_MONTHS) * length(Catalog.EXPERIMENTS)
end

Test.@testset "Top-level helpers (SwirlLMCloudBench module)" begin
    Test.@test SwirlLMCloudBench.cases_range() == Catalog.CLOUDBENCH_CASE_INDICES
    Test.@test SwirlLMCloudBench.months_tuple() == Catalog.CLOUDBENCH_MONTHS
    ev = SwirlLMCloudBench.experiments_val()
    Test.@test length(ev) == length(Catalog.EXPERIMENTS)
    Test.@test ev[1] === Val(:amip)
end

Test.@testset "Optional extensions not loaded without extra packages" begin
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt) === nothing
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchOhMyThreadsExt) === nothing
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchDistributedExt) === nothing
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchThermodynamicsExt) === nothing
end

Test.@testset "show (compact REPL-style)" begin
    inst = S.CloudBenchInstance(0, 4, :amip)
    s = sprint(show, inst)
    Test.@test occursin("CloudBenchInstance(0, 4,", s) && occursin("amip", s)
    mktempdir() do dir
        csv = joinpath(dir, "s.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            for i in 1:3
                zv = Float32(i)
                tv = 280f0 + zv
                println(
                    io,
                    "$(zv),$(tv),$(tv),0.01,0.0,0.0,0.0,0.0,0.0,$(tv),101325.0,1.0,0.0",
                )
            end
        end
        snd = S.CloudBenchSounding(csv)
        # the level count is what the compact form reports, so it has to be the real one
        Test.@test occursin("3 vertical levels", sprint(show, snd))
    end
    sim = S.CloudBenchSimulation(0, 4, :amip)
    plain = sprint() do io
        show(io, MIME("text/plain"), sim)
    end
    Test.@test occursin("CloudBenchSimulation", plain) && occursin("metadata:", plain) && occursin("instance:", plain)
end

Test.@testset "OhMyThreads extension" begin
    using OhMyThreads: OhMyThreads
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchOhMyThreadsExt) !== nothing
    Test.@test SwirlLMCloudBench.cloudbench_tmap(x -> 2x, [1, 2, 3]) == [2, 4, 6]
end

Test.@testset "Distributed extension" begin
    using Distributed: Distributed
    Test.@test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchDistributedExt) !== nothing
    Test.@test SwirlLMCloudBench.cloudbench_pmap_download_raw!(
        S.CloudBenchSimulation[],
        "/tmp/cloudbench_pmap_empty_test_root",
    ) == String[]
    empty_sel = S.CloudBenchSelection(0:-1, (1,), (:amip,))
    Test.@test length(empty_sel) == 0
    Test.@test SwirlLMCloudBench.cloudbench_pmap_download_raw!(empty_sel, "/tmp/cloudbench_pmap_empty_sel_root") ==
        String[]
end

include("unit_thermodynamics_backends.jl")

