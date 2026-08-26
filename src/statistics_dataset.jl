using NCDatasets: NCDatasets

"""Public bucket holding the post-processed CloudBench statistics."""
const GCS_STATISTICS_BASE = "https://storage.googleapis.com/cloudbench-statistics"

"""
The single netCDF of post-processed statistics for every published simulation, with each case's metadata
(location, GCM column conditions) alongside. About 184 MB.
"""
const CLOUDBENCH_STATISTICS_FILENAME = "cloudbench_statistics.nc"

"""HTTPS URL of [`CLOUDBENCH_STATISTICS_FILENAME`](@ref)."""
cloudbench_statistics_url() = join([GCS_STATISTICS_BASE, CLOUDBENCH_STATISTICS_FILENAME], '/')

"""
    cloudbench_statistics_path(root=nothing) -> String

Where the statistics file lives locally. `root` defaults to [`Config.raw_download_root`](@ref); the file sits at its
top level rather than under a case directory, because it spans every case.
"""
function cloudbench_statistics_path(root::Union{Nothing,AbstractString} = nothing)
    r = root === nothing ? _Pkg.Config.raw_download_root() : String(normpath(expanduser(String(root))))
    return joinpath(r, CLOUDBENCH_STATISTICS_FILENAME)
end

"""
    ensure_cloudbench_statistics_local!(; root=nothing, verbose=nothing) -> String

Download the statistics netCDF unless it is already present, and return its path.
"""
function ensure_cloudbench_statistics_local!(;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    dest = cloudbench_statistics_path(root)
    isfile(dest) && return dest
    url = cloudbench_statistics_url()
    _Pkg.cloudbench_info("Downloading CloudBench statistics"; verbose, url, dest)
    return _download_atomic(url, dest)
end

"""
    open_cloudbench_statistics(f; root=nothing, verbose=nothing)
    open_cloudbench_statistics(; root=nothing, verbose=nothing) -> NCDataset

Open the statistics netCDF, downloading it first if needed. The `f` form closes the dataset afterwards.
"""
function open_cloudbench_statistics(;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    return NCDatasets.NCDataset(ensure_cloudbench_statistics_local!(; root, verbose), "r")
end

function open_cloudbench_statistics(
    f::Function;
    root::Union{Nothing,AbstractString} = nothing,
    verbose::Union{Nothing,Bool} = nothing,
)
    return NCDatasets.NCDataset(f, ensure_cloudbench_statistics_local!(; root, verbose), "r")
end
