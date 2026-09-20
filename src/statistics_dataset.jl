using NCDatasets: NCDatasets
using Artifacts: Artifacts
using ..Catalog: Catalog

"""Public bucket holding the post-processed CloudBench statistics."""
const GCS_STATISTICS_BASE = "https://storage.googleapis.com/cloudbench-statistics"

"""
The single netCDF of post-processed statistics for every published simulation, with each case's metadata
(location, GCM column conditions) alongside. 193,294,481 bytes.

Dimensioned `site = 500`, `month = 4`, `experiment = 5`, `z = 480`. Ten variables are profiles on
`(z, experiment, month, site)` and the rest are `(experiment, month, site)` tables; every variable is
contiguous and uncompressed. It carries diagnostics `data.zarr` does not — `cloud_feedback_lw`,
`cloud_feedback_sw`, `lts`, `eis`, `subsidence_4km`, `cloud_top_height` — and the per-case metadata
`lat`, `lon`, `sst`, `p_sfc`, `zenith`, `insolation`, `theta_li_sfc`, `q_t_sfc`.
"""
const CLOUDBENCH_STATISTICS_FILENAME = "cloudbench_statistics.nc"

"""Vertical dimension of the statistics profiles, the LES grid's 480 levels."""
const CLOUDBENCH_STATISTICS_NZ = 480

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

"""
    open_cloudbench_statistics_remote(f; verbose=nothing)
    open_cloudbench_statistics_remote(; verbose=nothing) -> NCDataset

Open the statistics netCDF **over HTTPS without downloading it**, via netcdf-c's byte-range reader
(`#mode=bytes`). The `f` form closes the dataset afterwards.

Reads fetch only the bytes they need, and the file's layout makes that cheap for the access this is
for: it is contiguous and uncompressed with `z` fastest-varying.

Use [`cloudbench_statistics_profile`](@ref) / [`cloudbench_statistics_scalar`](@ref) to read a case,
which index the fast axis by construction.
"""
function open_cloudbench_statistics_remote(; verbose::Union{Nothing,Bool} = nothing)
    url = cloudbench_statistics_url() * "#mode=bytes"
    _Pkg.cloudbench_info("Opening CloudBench statistics over HTTPS byte ranges"; verbose, url)
    return NCDatasets.NCDataset(url, "r")
end

function open_cloudbench_statistics_remote(f::Function; verbose::Union{Nothing,Bool} = nothing)
    url = cloudbench_statistics_url() * "#mode=bytes"
    _Pkg.cloudbench_info("Opening CloudBench statistics over HTTPS byte ranges"; verbose, url)
    return NCDatasets.NCDataset(f, url, "r")
end

# --- lazy artifact ----------------------------------------------------------------------------- #

"""Artifacts.toml entry name for the bundled statistics netCDF."""
const CLOUDBENCH_STATISTICS_ARTIFACT = "cloudbench_statistics"

"""
    cloudbench_statistics_artifact_path() -> String

Path to the statistics netCDF inside its `Pkg` artifact, downloading the artifact once into the
depot on first call.

The same file [`ensure_cloudbench_statistics_local!`](@ref) fetches
"""
function cloudbench_statistics_artifact_path()
    toml = joinpath(_Pkg.Paths.package_root(), "Artifacts.toml")
    p = joinpath(Artifacts.@artifact_str(CLOUDBENCH_STATISTICS_ARTIFACT), CLOUDBENCH_STATISTICS_FILENAME)
    isfile(p) || error("the $(CLOUDBENCH_STATISTICS_ARTIFACT) artifact does not contain $(CLOUDBENCH_STATISTICS_FILENAME)")
    return p
end

"""
    open_cloudbench_statistics_artifact(f)
    open_cloudbench_statistics_artifact() -> NCDataset

Open the statistics netCDF from its `Pkg` artifact (see [`cloudbench_statistics_artifact_path`](@ref)).
The `f` form closes the dataset afterwards.
"""
open_cloudbench_statistics_artifact() = NCDatasets.NCDataset(cloudbench_statistics_artifact_path(), "r")
open_cloudbench_statistics_artifact(f::Function) =
    NCDatasets.NCDataset(f, cloudbench_statistics_artifact_path(), "r")

# --- case-keyed reads -------------------------------------------------------------------------- #

"""
    cloudbench_statistics_indices(ds, inst) -> (; site, month, experiment)

One-based indices of `inst` along the statistics file's `site`, `month` and `experiment` coordinate
variables. Throws if the case is absent.
"""
function cloudbench_statistics_indices(ds, inst::CloudBenchInstance)
    site = findfirst(==(inst.site_id), Array(ds["site"][:]))
    site === nothing && throw(ArgumentError("site_id $(inst.site_id) is not in the statistics file"))
    month = findfirst(==(inst.month), Array(ds["month"][:]))
    month === nothing && throw(ArgumentError("month $(inst.month) is not in the statistics file"))
    seg = Catalog.gcs_path_segment(inst.experiment)
    experiments = String.(Array(ds["experiment"][:]))
    experiment = findfirst(e -> Catalog.gcs_path_segment(e) == seg, experiments)
    experiment === nothing &&
        throw(ArgumentError("experiment $(repr(seg)) is not in the statistics file; got $(experiments)"))
    return (; site, month, experiment)
end

"""
    cloudbench_statistics_profile(ds, inst, name) -> Vector

The `(z,)` profile of variable `name` for one case. Indexes `z` whole and the other three axes
singly, which is the file's contiguous direction.
"""
function cloudbench_statistics_profile(ds, inst::CloudBenchInstance, name::AbstractString)
    i = cloudbench_statistics_indices(ds, inst)
    v = ds[name]
    ndims(v) == 4 || throw(ArgumentError("$(name) is not a profile variable; it has $(ndims(v)) dimensions"))
    return v[:, i.experiment, i.month, i.site]
end

"""
    cloudbench_statistics_scalar(ds, inst, name)

The per-case value of variable `name`, from an `(experiment, month, site)` table.
"""
function cloudbench_statistics_scalar(ds, inst::CloudBenchInstance, name::AbstractString)
    i = cloudbench_statistics_indices(ds, inst)
    v = ds[name]
    ndims(v) == 3 || throw(ArgumentError("$(name) is not a per-case scalar; it has $(ndims(v)) dimensions"))
    return v[i.experiment, i.month, i.site]
end

cloudbench_statistics_indices(ds, sim::CloudBenchSimulation) =
    cloudbench_statistics_indices(ds, cloudbench_instance(sim))
cloudbench_statistics_profile(ds, sim::CloudBenchSimulation, name::AbstractString) =
    cloudbench_statistics_profile(ds, cloudbench_instance(sim), name)
cloudbench_statistics_scalar(ds, sim::CloudBenchSimulation, name::AbstractString) =
    cloudbench_statistics_scalar(ds, cloudbench_instance(sim), name)
