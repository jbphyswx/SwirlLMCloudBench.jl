using Test: @test, @testset, @test_throws
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

@testset "Catalog" begin
    @test length(Catalog.CLOUDBENCH_CASE_INDICES) == 500
    @test first(Catalog.CLOUDBENCH_CASE_INDICES) == 0
    @test last(Catalog.CLOUDBENCH_CASE_INDICES) == 499
    @test Catalog.CLOUDBENCH_MONTHS == (1, 4, 7, 10)
    @test Catalog.n_cases() == 500
    @test Set(Catalog.experiment_names()) == Set(collect(Catalog.EXPERIMENTS))
    @test Catalog.parse_experiment("amip") === :amip
    @test Catalog.parse_experiment(:amip_p4k) === :amip_p4k
    @test_throws ArgumentError Catalog.parse_experiment("nope")
    @test Catalog.valid_case_index(0) && Catalog.valid_case_index(499)
    @test !Catalog.valid_case_index(-1) && !Catalog.valid_case_index(500)
    @test Catalog.valid_month(1) && !Catalog.valid_month(2)
    @test Catalog.gcs_path_segment(:amip) == "amip"
    @test Catalog.gcs_path_segment(:amip_p4k) == "amip-p4k"
    @test Catalog.gcs_path_segment("amip_p4k") == "amip-p4k"
    @test Catalog.gcs_path_segment(Catalog.amip) == "amip"
    @test Catalog.gcs_path_segment(Catalog.amip_p4k) == "amip-p4k"
    @test Symbol(Catalog.amip_p4k) === :amip_p4k
    @test Catalog.CloudBenchExperiment(:amip_4xco2) === Catalog.amip_4xco2
    @test Catalog.CloudBenchExperiment("amip-p4k") === Catalog.amip_p4k
end

@testset "Paths" begin
    root = Paths.package_root()
    @test isdir(root)
    @test isfile(joinpath(root, "Project.toml"))
    dr = Paths.default_data_root()
    @test occursin("data", dr)
    cr = Paths.default_cache_root()
    @test occursin("scratch", cr)
end

@testset "Config" begin
    withenv(
        "SWIRL_LM_CLOUDBENCH_DATA_ROOT" => "",
        "SWIRL_LM_CLOUDBENCH_CACHE_ROOT" => "",
        "SWIRL_LM_CLOUDBENCH_RAW_ROOT" => "",
    ) do
        @test Config.data_root() == Paths.default_data_root()
        @test Config.cache_root() == Paths.default_cache_root()
    end
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_DATA_ROOT" => d) do
            @test Config.data_root() == normpath(d)
        end
    end
    @test Config.parse_bool_env("__SWIRL_LM_TEST_BOOL_XX__", false) == false
    withenv("__SWIRL_LM_TEST_BOOL_XX__" => "true") do
        @test Config.parse_bool_env("__SWIRL_LM_TEST_BOOL_XX__", false) == true
    end
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_RAW_ROOT" => d) do
            @test Config.raw_download_root() == normpath(d)
        end
    end
end

@testset "CaseDirs.resolved_case_dir (canonical bucket layout)" begin
    mktempdir() do d
        withenv("SWIRL_LM_CLOUDBENCH_DATA_ROOT" => d) do
            p = CaseDirs.resolved_case_dir(10, 7, :amip)
            @test p == joinpath(d, "10", "7", "amip")
            # consistent with the download / bucket layout
            @test p == S.local_simulation_dir(d, S.CloudBenchInstance(10, 7, :amip))
        end
        @test CaseDirs.resolved_case_dir(0, 4, :amip_p4k; root = d) == joinpath(d, "0", "4", "amip-p4k")
    end
    @test_throws ArgumentError CaseDirs.resolved_case_dir(500, 7, :amip)
    @test_throws ArgumentError CaseDirs.resolved_case_dir(0, 2, :amip)
    @test_throws ArgumentError CaseDirs.resolved_case_dir(0, 7, :nope)
end

@testset "CloudBenchSimulation and Simulation URLs" begin
    sl = S.CloudBenchSimulation(0, 1, :amip)
    @test sl.site_id == 0 && sl.month == 1 && sl.experiment === Catalog.amip
    @test isbitstype(S.CloudBenchInstance)
    sl2 = S.CloudBenchSimulation(Dict("site_id" => 7, "month" => 4, "experiment" => "amip"))
    @test sl2.site_id == 7 && sl2.month == 4
    @test_throws ArgumentError S.CloudBenchSimulation(Dict{String,Any}())
    u = S.cloudbench_sounding_url(sl)
    @test occursin("storage.googleapis.com/cloudbench-simulation-output", u)
    @test occursin("/0/1/amip/sounding.csv", u)
    u3 = S.cloudbench_sounding_url(0, 1, :amip)
    @test u == u3
    z = S.cloudbench_zarr_url(0, 4, :amip_p4k)
    @test occursin("/0/4/amip-p4k/data.zarr", z)
    @test S.cloudbench_zarr_url(S.CloudBenchSimulation(0, 4, :amip_p4k)) == z
    purl = S.cloudbench_parameters_url(0, 1, :amip)
    @test occursin("/0/1/amip/parameters.json", purl)
end

@testset "local paths (bucket layout)" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    root = "/tmp/cloudbench_mirror"
    d = S.local_simulation_dir(root, sim)
    @test d == joinpath(root, "0", "1", "amip")
    @test S.sounding_path(sim, root) == joinpath(d, "sounding.csv")
    @test S.parameters_path(sim, root) == joinpath(d, "parameters.json")
    @test S.zarr_local_path(sim, root) == joinpath(d, "data.zarr")
    sim2 = S.CloudBenchSimulation(0, 4, :amip_p4k)
    @test S.local_simulation_dir(root, sim2) == joinpath(root, "0", "4", "amip-p4k")
end

@testset "CloudBenchParameters JSON" begin
    js = """
    {"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
    "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
    "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt"}
    """
    cp = S.parse_cloudbench_parameters(js)
    @test cp isa S.CloudBenchParameters{Float32,String}
    @test cp isa S.CloudBenchParametersDefault
    @test cp.experiment == "amip" && cp.month == 1
    @test cp.latitude ≈ 16.5f0 && cp.longitude ≈ -141.875f0
    # opt-in isbits inline string storage still works (parametric)
    cp_inline = S.parse_cloudbench_parameters(js; string_type = InlineStrings.String127)
    @test cp_inline isa S.CloudBenchParametersInline
    @test cp_inline.experiment == "amip"
    mktempdir() do dir
        p = joinpath(dir, "p.json")
        write(p, js)
        cp2 = S.read_cloudbench_parameters(p)
        @test cp2.sounding_path == "/x/sounding.csv"
    end
    js_extra = """
    {"experiment":"amip","month":1,"latitude":16.5,"longitude":-141.875,"sst":297.5,"p_sfc":101447.7,
    "theta_li_sfc":296.36,"q_t_sfc":0.018,"zenith":0.89,"insolation":333.0,"irrad":532.0,
    "sounding_path":"/x/sounding.csv","config_path":"/x/config.pbtxt","unexpected":1}
    """
    @test_throws ArgumentError S.parse_cloudbench_parameters(js_extra)
    # strict=false ignores unknown keys (forward-compatible)
    @test S.parse_cloudbench_parameters(js_extra; strict = false) isa S.CloudBenchParametersDefault
end

@testset "open_zarr_local missing store" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    mktempdir() do root
        @test_throws ArgumentError S.open_zarr_local(sim, root)
    end
end

@testset "download_cloudbench_raw! zarr=false only" begin
    sim = S.CloudBenchSimulation(0, 1, :amip)
    @test_throws ArgumentError S.download_cloudbench_raw!(sim; zarr = true)
end

@testset "load_cloudbench_simulation local_mirror=false" begin
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
        @test r isa S.CloudBenchSimulationRemoteLoaded
        @test r.metadata.parameters.experiment == "amip"
        @test length(r.metadata.sounding.z) == 2
        @test r.output isa S.RemoteCloudBenchZarrOutput
    end
end

if get(ENV, "CLOUDBENCH_NETWORK_TEST", "") == "1"
    @testset "download_cloudbench_raw! (network)" begin
        mktempdir() do root
            sim = S.CloudBenchSimulation(0, 1, :amip)
            dir = S.download_cloudbench_raw!(sim; root = root)
            @test dir == S.local_simulation_dir(root, sim)
            @test isfile(S.sounding_path(sim, root))
            @test isfile(S.parameters_path(sim, root))
            inst = S.CloudBenchInstance(0, 1, :amip)
            bundle = S.load_cloudbench_simulation(inst; root = root, download = false)
            @test S.cloudbench_instance(bundle) == inst
            @test bundle isa S.CloudBenchSimulationLoaded
            @test bundle.metadata.parameters.experiment == "amip"
            @test bundle.output isa S.LocalCloudBenchMirrorOutput
            @test bundle.output.root == root
        end
    end

    @testset "bundled soundings artifact (network)" begin
        inst = S.CloudBenchInstance(0, 1, :amip)
        d = S.bundled_soundings_dir()                       # downloads the ~10 MB artifact once
        @test isdir(d)
        @test isfile(S.bundled_sounding_path(inst))
        @test isfile(S.bundled_parameters_path(inst))
        snd = S.bundled_sounding(inst)
        @test snd isa S.CloudBenchSounding && length(snd.z) >= 2
    end
end

@testset "q_c split (Swirl-LM condensate_liquid_fraction)" begin
    @test S.condensate_liquid_fraction(233.0) == 0.0
    @test S.condensate_liquid_fraction(273.15) == 1.0
    q_l, q_i = S.split_q_c(0.1, 253.15)
    @test q_l + q_i ≈ 0.1
    @test q_l > 0 && q_i > 0
    @test S.condensate_liquid_fraction(233.0) == 0.0
    @test S.split_q_c(0.1, 253.15) == S.split_q_c(0.1, 253.15)
end

@testset "CloudBenchSounding and write_sounding_netcdf!" begin
    using NCDatasets: NCDatasets
    @test S.CLOUDBENCH_SOUNDING_CSV_HEADER ==
          "z,theta_li,temperature,q_t,u,v,w,T_adv_src,q_t_adv_src,T,p,rho,cld_frac"
    mktempdir() do dir
        csv = joinpath(dir, "sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
            println(io, "100,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
        end
        s = S.CloudBenchSounding(csv)
        @test s isa S.CloudBenchSounding{Float32,Vector{Float32}}
        @test length(s.z) == 2
        @test s.T == s.T_column
        @test_throws DimensionMismatch S.CloudBenchSounding{Float32,Vector{Float32}}(
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
        @test isfile(nc)
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
                @test haskey(g, name)
                @test size(g[name]) == (2,)
            end
        end
        nc2 = joinpath(dir, "out2.nc")
        S.write_sounding_netcdf!(nc2, csv, "site2")
        @test isfile(nc2)
    end
end

@testset "CloudBenchSounding parse errors and cloudbench_sounding_zt_matrices" begin
    mktempdir() do dir
        csv = joinpath(dir, "rich_sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,300,280,0.01,1,2,0.1,1e-5,1e-8,280,1e5,1.2,0.3")
            println(io, "100,290,270,0.008,1,2,-0.05,2e-5,2e-8,270,9e4,1.0,0.2")
        end
        s = S.CloudBenchSounding(csv)
        @test occursin("vertical level", sprint(show, s))
        nt = S.read_cloudbench_sounding_columns(csv, Float32)
        @test nt.T_column == s.T_column
        m = S.cloudbench_sounding_zt_matrices(s, 4)
        @test m.w[1, 1] == 0.1f0 && m.w[1, 3] == 0.1f0
        @test m.temperature_horizontal_advective_tendency[1, 1] ≈ 1.0f-5 + 0.1f0 * (-0.1f0)
        @test m.temperature_horizontal_advective_tendency[2, 2] ≈ 2.0f-5 + (-0.05f0) * (-0.1f0)
        @test m.q_t_horizontal_advective_tendency[1, 1] ≈ 1.0f-8 + 0.1f0 * (-2.0f-5)
        @test m.q_t_horizontal_advective_tendency[2, 2] ≈ 2.0f-8 + (-0.05f0) * (-2.0f-5)
        Tadv = S._profile_replicated(s.T_adv_src, length(s.z), 4)
        Qadv = S._profile_replicated(s.q_t_adv_src, length(s.z), 4)
        @test m.temperature_horizontal_advective_tendency ≈ Tadv .+ m.temperature_vertical_advection
        @test m.q_t_horizontal_advective_tendency ≈ Qadv .+ m.q_t_vertical_advection
        g = 9.80665f0
        @test m.vertical_pressure_velocity[1, 1] ≈ -1.2f0 * g * 0.1f0
    end
    mktempdir() do dir
        bad = joinpath(dir, "bad.csv")
        open(bad, "w") do io
            println(io, "z,temperature,q_t,u,v,rho")
            println(io, "0,280,0.01,1,2,1.2")
            println(io, "100,270,0.008,1,2,1.0")
        end
        @test_throws ErrorException S.CloudBenchSounding(bad)
    end
end

@testset "value semantics (==/hash)" begin
    mktempdir() do dir
        csv = joinpath(dir, "sounding.csv")
        open(csv, "w") do io
            println(io, S.CLOUDBENCH_SOUNDING_CSV_HEADER)
            println(io, "0,288,288,0.01,0.0,0.0,0.0,0.0,0.0,288,101325.0,1.2,0.0")
            println(io, "100,280,280,0.008,1.0,0.5,0.0,0.0,0.0,280,100000.0,1.0,0.0")
        end
        s1 = S.CloudBenchSounding(csv)
        s2 = S.CloudBenchSounding(csv)   # independently parsed: equal content, distinct Vectors
        @test s1 == s2                    # was broken before (fell back to === on Vector fields)
        @test hash(s1) == hash(s2)
        @test length(Set([s1, s2])) == 1
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
        @test a isa S.CloudBenchSimulationLoaded
        @test a == b                      # full metadata chain incl. parsed sounding
        @test hash(a) == hash(b)
    end
    i1 = S.CloudBenchInstance(3, 4, :amip_p4k)
    i2 = S.CloudBenchInstance(3, 4, :amip_p4k)
    @test i1 == i2 && hash(i1) == hash(i2)
    @test haskey(Dict(i1 => :x), i2)
end

@testset "split_q_c arrays + promotion" begin
    # mixed scalar types promote
    ql, qi = S.split_q_c(0.1f0, 253.15)
    @test ql + qi ≈ 0.1f0
    # array form returns two arrays (the documented data.zarr use)
    q_c = [0.1, 0.2, 0.0]
    T = [253.15, 233.0, 300.0]
    q_liq, q_ice = S.split_q_c(q_c, T)
    @test q_liq isa AbstractVector && q_ice isa AbstractVector
    @test q_liq .+ q_ice ≈ q_c
    @test q_ice[2] ≈ 0.2          # all ice at 233 K
    @test q_liq[3] ≈ 0.0          # all liquid at 300 K -> q_ice 0, but q_c is 0 here
    @test_throws DimensionMismatch S.split_q_c([0.1, 0.2], [253.15])
end

@testset "CloudBenchSelection (lazy)" begin
    sel = S.CloudBenchSelection((0, 1), (1,), (:amip, :amip_p4k))
    @test length(sel) == 4
    sims = collect(sel)
    @test length(sims) == 4
    @test sims[1] == S.CloudBenchSimulation(0, 1, :amip)
    g = S.each_simulation(sel)
    @test collect(g) == sims
    full = S.CloudBenchSelection()
    @test length(full) == length(Catalog.CLOUDBENCH_CASE_INDICES) * length(Catalog.CLOUDBENCH_MONTHS) * length(Catalog.EXPERIMENTS)
end

@testset "Top-level helpers (SwirlLMCloudBench module)" begin
    @test SwirlLMCloudBench.cases_range() == Catalog.CLOUDBENCH_CASE_INDICES
    @test SwirlLMCloudBench.months_tuple() == Catalog.CLOUDBENCH_MONTHS
    ev = SwirlLMCloudBench.experiments_val()
    @test length(ev) == length(Catalog.EXPERIMENTS)
    @test ev[1] === Val(:amip)
end

@testset "Optional extensions not loaded without extra packages" begin
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchClimaAtmosExt) === nothing
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchOhMyThreadsExt) === nothing
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchDistributedExt) === nothing
end

@testset "show (compact REPL-style)" begin
    inst = S.CloudBenchInstance(0, 4, :amip)
    s = sprint(show, inst)
    @test occursin("CloudBenchInstance(0, 4,", s) && occursin("amip", s)
    @test length(s) < 80
    csv = joinpath(mktempdir(), "s.csv")
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
    @test length(sprint(show, snd)) < 120
    @test occursin("3 vertical levels", sprint(show, snd))
    js = """{"experiment":"amip","month":4,"latitude":0.0,"longitude":0.0,"sst":300.0,"p_sfc":1e5,
        "theta_li_sfc":300.0,"q_t_sfc":0.01,"zenith":0.0,"insolation":0.0,"irrad":0.0,
        "sounding_path":"/a.csv","config_path":"/b.pbtxt"}"""
    cp = S.parse_cloudbench_parameters(js)
    @test length(sprint(show, cp)) < 200
    sim = S.CloudBenchSimulation(0, 4, :amip)
    plain = sprint() do io
        show(io, MIME("text/plain"), sim)
    end
    @test occursin("CloudBenchSimulation", plain) && occursin("metadata:", plain) && occursin("instance:", plain)
end

@testset "open_zarr methods" begin
    @test hasmethod(S.open_zarr, Tuple{Int,Int,Symbol})
    @test hasmethod(S.open_zarr, Tuple{Int,Int,String})
    @test hasmethod(S.open_zarr, Tuple{Int,Int,Catalog.CloudBenchExperiment})
    @test hasmethod(S.open_zarr, Tuple{S.CloudBenchSimulation})
end

@testset "OhMyThreads extension" begin
    using OhMyThreads: OhMyThreads
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchOhMyThreadsExt) !== nothing
    @test SwirlLMCloudBench.cloudbench_tmap(x -> 2x, [1, 2, 3]) == [2, 4, 6]
end

@testset "Distributed extension" begin
    using Distributed: Distributed
    @test Base.get_extension(SwirlLMCloudBench, :SwirlLMCloudBenchDistributedExt) !== nothing
    @test SwirlLMCloudBench.cloudbench_pmap_download_raw!(
        S.CloudBenchSimulation[],
        "/tmp/cloudbench_pmap_empty_test_root",
    ) == String[]
    empty_sel = S.CloudBenchSelection(0:-1, (1,), (:amip,))
    @test length(empty_sel) == 0
    @test SwirlLMCloudBench.cloudbench_pmap_download_raw!(empty_sel, "/tmp/cloudbench_pmap_empty_sel_root") ==
        String[]
end

