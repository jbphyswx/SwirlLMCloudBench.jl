using Downloads: Downloads
using ..Catalog: Catalog
using ..Config: Config

"""
    ensure_cloudbench_sounding_local!(sim; root=nothing) -> String
    ensure_cloudbench_sounding_local!(site_id, month, experiment; root=nothing) -> String

Download `sounding.csv` once and return the local path (network I/O).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).

Uses the bucket-shaped layout under [`raw_download_root`](@ref) when `root === nothing`, otherwise [`sounding_path`](@ref)(`sim`, `root`).

`verbose` controls download messages for this call only (`nothing` → [`cloudbench_logging`](@ref)).
"""
function ensure_cloudbench_sounding_local!(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment};
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    r = root === nothing ? Config.raw_download_root() : String(normpath(expanduser(String(root))))
    inst = CloudBenchInstance(site_id, month, experiment)
    dest = sounding_path(inst, r)
    isfile(dest) && return dest
    mkpath(dirname(dest))
    url = cloudbench_sounding_url(inst)
    _Pkg.cloudbench_info("Downloading CloudBench sounding.csv"; verbose, url, dest)
    Downloads.download(url, dest)
    return dest
end

function ensure_cloudbench_sounding_local!(
    inst::CloudBenchInstance;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    r = root === nothing ? Config.raw_download_root() : String(normpath(expanduser(String(root))))
    dest = sounding_path(inst, r)
    isfile(dest) && return dest
    mkpath(dirname(dest))
    url = cloudbench_sounding_url(inst)
    _Pkg.cloudbench_info("Downloading CloudBench sounding.csv"; verbose, url, dest)
    Downloads.download(url, dest)
    return dest
end

function ensure_cloudbench_sounding_local!(
    sim::CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    return ensure_cloudbench_sounding_local!(cloudbench_instance(sim); root = root, verbose = verbose)
end
