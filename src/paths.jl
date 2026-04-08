"""
Filesystem layout for local SwirlLM CloudBench mirrors and package artifacts.

Override roots with environment variables documented in `SwirlLMCloudBench.Config`.
"""
module Paths

export package_root, default_data_root, default_cache_root, case_artifact_dir

"""Directory containing this package's `Project.toml` (the `SwirlLMCloudBench.jl` folder)."""
function package_root()::String
    normpath(joinpath(@__DIR__, ".."))
end

"""Default directory for downloaded or mirrored CloudBench fields (see `Config.data_root`)."""
function default_data_root()::String
    joinpath(package_root(), "data")
end

"""Default scratch/cache directory for derived files and locks."""
function default_cache_root()::String
    joinpath(package_root(), "scratch")
end

"""
    case_artifact_dir(root, experiment, case_index; month=nothing)

Return a stable subdirectory path for one case under `root` (typically `data_root()`).
`experiment` is a `Symbol` (e.g. `:amip`). `case_index` is an integer in the CloudBench ensemble range.
If `month` is given, it is included in the path for seasonally split layouts.
"""
function case_artifact_dir(
    root::AbstractString,
    experiment::Symbol,
    case_index::Integer;
    month::Union{Nothing,Integer} = nothing,
)::String
    base = joinpath(String(root), String(experiment), string(Int(case_index)))
    month === nothing && return base
    joinpath(base, "month_" * string(Int(month)))
end

end # module Paths
