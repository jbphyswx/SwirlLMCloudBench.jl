using Artifacts: @artifact_str
using LazyArtifacts: LazyArtifacts   # loaded for its side effect: enables lazy download of `lazy = true` artifacts

"""
    bundled_soundings_dir() -> String

Path to the bundled-soundings `Pkg` artifact directory: every CloudBench `sounding.csv` + `parameters.json` laid out as
the public bucket `[dir]/[site_id]/[month]/[experiment]/`. The ~10 MB artifact is downloaded **once** into the Julia
depot on first call (lazy) and then served locally — so iterating the catalog needs no per-case GCS requests.

The live HTTPS path still works for ad-hoc use ([`ensure_cloudbench_sounding_local!`](@ref) /
[`download_cloudbench_raw!`](@ref)); this is the offline/bulk alternative.
"""
bundled_soundings_dir() = @artifact_str("cloudbench_soundings")

"""Local path to the bundled `sounding.csv` for `inst`/`sim` inside [`bundled_soundings_dir`](@ref)."""
function bundled_sounding_path(inst::CloudBenchInstance)
    p = sounding_path(inst, bundled_soundings_dir())
    isfile(p) || error("bundled sounding.csv missing at $(p) (the artifact should bundle the full catalog)")
    return p
end
bundled_sounding_path(sim::CloudBenchSimulation) = bundled_sounding_path(cloudbench_instance(sim))

"""Local path to the bundled `parameters.json` for `inst`/`sim` inside [`bundled_soundings_dir`](@ref)."""
function bundled_parameters_path(inst::CloudBenchInstance)
    p = parameters_path(inst, bundled_soundings_dir())
    isfile(p) || error("bundled parameters.json missing at $(p) (the artifact should bundle the full catalog)")
    return p
end
bundled_parameters_path(sim::CloudBenchSimulation) = bundled_parameters_path(cloudbench_instance(sim))

"""
    bundled_sounding(inst; eltype=Float32) -> CloudBenchSounding

Load a [`CloudBenchSounding`](@ref) from the bundled artifact (no network after the one-time artifact download).
"""
bundled_sounding(inst::CloudBenchInstance; eltype::Type{<:AbstractFloat} = Float32) =
    CloudBenchSounding(bundled_sounding_path(inst); eltype = eltype)
bundled_sounding(sim::CloudBenchSimulation; kwargs...) = bundled_sounding(cloudbench_instance(sim); kwargs...)
