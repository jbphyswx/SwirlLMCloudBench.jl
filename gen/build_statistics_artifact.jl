# Maintainer script: build the bundled CloudBench **statistics** artifact.
#
# Downloads `cloudbench_statistics.nc` (193 MB) into a staging tree, packs it into a content-addressed `Pkg`
# artifact, archives that to a `.tar.gz`, and prints the `git-tree-sha1`, the tarball `sha256`, and a
# ready-to-paste `Artifacts.toml` entry. 

# Usage (from the package directory):
#   pkg> activate gen 
#   julia> using Pkg; Pkg.instantiate()
#   julia> includ("gen/build_statistics_artifact.jl")
#
# Then:
#   1. Upload the printed `*.tar.gz` as a GitHub Release asset on jbphyswx/SwirlLMCloudBench.jl.
#   2. Paste the printed `[cloudbench_statistics]` block into `Artifacts.toml` (filling the release `url`).
#   3. `Simulation.cloudbench_statistics_artifact_path` then serves it offline.

using Pkg: Pkg
using SwirlLMCloudBench: SwirlLMCloudBench

function parse_args(argv)
    out = abspath("cloudbench_statistics.tar.gz")
    i = 1
    while i <= length(argv)
        if argv[i] == "--out"
            out = abspath(argv[i + 1])
            i += 1
        else
            error("unknown argument $(argv[i])")
        end
        i += 1
    end
    return (; out)
end

function main(argv)
    opts = parse_args(argv)
    println("Building statistics artifact from ", SwirlLMCloudBench.Simulation.cloudbench_statistics_url())

    hash = Pkg.Artifacts.create_artifact() do dir
        SwirlLMCloudBench.Simulation.ensure_cloudbench_statistics_local!(; root = dir, verbose = true)
        return nothing
    end

    tar_sha = Pkg.Artifacts.archive_artifact(hash, opts.out)
    sz = round(filesize(opts.out) / 1024 / 1024; digits = 1)

    println("\n=== artifact built ===")
    println("git-tree-sha1 : ", hash)
    println("tarball       : ", opts.out, "  (", sz, " MB)")
    println("tarball sha256: ", tar_sha)
    println("\nUpload the tarball as a GitHub Release asset, then add this to Artifacts.toml (fill in <url>):\n")
    println("""
    [cloudbench_statistics]
    git-tree-sha1 = "$(hash)"
    lazy = true

        [[cloudbench_statistics.download]]
        url = "<github-release-asset-url>/$(basename(opts.out))"
        sha256 = "$(tar_sha)"
    """)
    return nothing
end

main(ARGS)
