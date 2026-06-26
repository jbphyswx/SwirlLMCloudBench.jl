# Maintainer script: build the bundled CloudBench **soundings** artifact.
#
# Downloads `sounding.csv` (and, by default, `parameters.json`) for the full published catalog into a staging tree
# in bucket layout `[root]/[site_id]/[month]/[experiment]/`, packs it into a content-addressed `Pkg` artifact, archives
# that to a `.tar.gz`, and prints the `git-tree-sha1`, the tarball `sha256`, and a ready-to-paste `Artifacts.toml`
# entry. The whole sounding set is ~50 MB raw / ~20 MB gzipped (10,000 small CSVs), which is a good artifact (unlike
# the multi-TB `data.zarr`, which is streamed).
#
# Usage (from the package directory):
#   julia --project=gen -e 'using Pkg; Pkg.instantiate()'
#   julia --project=gen gen/build_sounding_artifact.jl                 # full catalog, soundings + parameters
#   julia --project=gen gen/build_sounding_artifact.jl --limit 20      # smoke test on 20 cases
#   julia --project=gen gen/build_sounding_artifact.jl --no-parameters # soundings only
#
# Then:
#   1. Upload the printed `*.tar.gz` as a GitHub Release asset on jbphyswx/SwirlLMCloudBench.jl.
#   2. Paste the printed `[cloudbench_soundings]` block into `Artifacts.toml` (filling the release `url`).
#   3. The runtime API (`Simulation.bundled_soundings_dir` / `bundled_sounding_path`) then serves them offline.

using Pkg.Artifacts: create_artifact, archive_artifact
using SwirlLMCloudBench: Simulation as S

function parse_args(argv)
    include_parameters = true
    limit = nothing
    ntasks = 32
    out = abspath("cloudbench_soundings.tar.gz")
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--no-parameters"
            include_parameters = false
        elseif a == "--limit"
            limit = parse(Int, argv[i + 1]); i += 1
        elseif a == "--ntasks"
            ntasks = parse(Int, argv[i + 1]); i += 1
        elseif a == "--out"
            out = abspath(argv[i + 1]); i += 1
        else
            error("unknown argument $(a)")
        end
        i += 1
    end
    return (; include_parameters, limit, ntasks, out)
end

function main(argv)
    opts = parse_args(argv)
    sims = collect(S.each_simulation(S.CloudBenchSelection()))
    opts.limit === nothing || (sims = sims[1:min(opts.limit, length(sims))])
    n = length(sims)
    println("Building soundings artifact: $(n) cases, parameters=$(opts.include_parameters), ntasks=$(opts.ntasks)")

    # Populate a fresh content-addressed artifact directory by downloading into it (atomic, skip-if-present).
    done = Threads.Atomic{Int}(0)
    hash = create_artifact() do dir
        asyncmap(sims; ntasks = opts.ntasks) do sim
            S.download_cloudbench_raw!(
                S.cloudbench_instance(sim);
                root = dir,
                sounding = true,
                parameters = opts.include_parameters,
            )
            c = Threads.atomic_add!(done, 1) + 1
            c % 250 == 0 && println("  downloaded $(c)/$(n)")
            return nothing
        end
        return nothing
    end

    # archive_artifact writes the tarball to `opts.out` and returns its sha256 (hex string)
    tar_sha = archive_artifact(hash, opts.out)
    tarball = opts.out
    sz = round(filesize(tarball) / 1024 / 1024; digits = 1)

    println("\n=== artifact built ===")
    println("git-tree-sha1 : ", hash)
    println("tarball       : ", tarball, "  (", sz, " MB)")
    println("tarball sha256: ", tar_sha)
    println("\nUpload the tarball as a GitHub Release asset, then add this to Artifacts.toml (fill in <url>):\n")
    println("""
    [cloudbench_soundings]
    git-tree-sha1 = "$(hash)"
    lazy = true

        [[cloudbench_soundings.download]]
        url = "<github-release-asset-url>/$(basename(tarball))"
        sha256 = "$(tar_sha)"
    """)
    return nothing
end

main(ARGS)
