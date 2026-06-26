"""
Filesystem layout for local SwirlLM CloudBench mirrors and package artifacts.

Override roots with environment variables documented in `SwirlLMCloudBench.Config`.
"""
module Paths

export package_root, default_data_root, default_cache_root

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

end # module Paths
