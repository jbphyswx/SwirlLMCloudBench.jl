"""
Runtime configuration from environment variables.

All paths are normalized with `normpath`. Empty strings in the environment are treated as unset.
"""
module Config

using Scratch: Scratch
using ..Paths: Paths

export data_root, cache_root, raw_download_root, parse_bool_env, parse_optional_string

const ENV_DATA_ROOT = "SWIRL_LM_CLOUDBENCH_DATA_ROOT"
const ENV_CACHE_ROOT = "SWIRL_LM_CLOUDBENCH_CACHE_ROOT"
const ENV_RAW_ROOT = "SWIRL_LM_CLOUDBENCH_RAW_ROOT"

function parse_optional_string(name::String)::Union{Nothing,String}
    raw = strip(get(ENV, name, ""))
    isempty(raw) && return nothing
    return normpath(expanduser(raw))
end

"""
    data_root() -> String

Root directory for CloudBench inputs mirrored or downloaded locally.

Environment: `SWIRL_LM_CLOUDBENCH_DATA_ROOT`. When unset, defaults to `Paths.default_data_root()`.
"""
function data_root()::String
    p = parse_optional_string(ENV_DATA_ROOT)
    p === nothing && return Paths.default_data_root()
    return p
end

"""
    cache_root() -> String

Scratch directory for derived artifacts, locks, and temporary downloads.

Environment: `SWIRL_LM_CLOUDBENCH_CACHE_ROOT`. When unset, defaults to `Paths.default_cache_root()`.
"""
function cache_root()::String
    p = parse_optional_string(ENV_CACHE_ROOT)
    p === nothing && return Paths.default_cache_root()
    return p
end

"""
    raw_download_root() -> String

Default parent directory for CloudBench raw bucket layout
`[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/` (see `Simulation.local_simulation_dir` in the `Simulation` module).

Precedence:

1. Environment `SWIRL_LM_CLOUDBENCH_RAW_ROOT` when set (absolute path recommended for HPC/CI).
2. Otherwise [`Scratch.get_scratch!`](https://github.com/JuliaPackaging/Scratch.jl) on the package module with key `\"cloudbench_raw\"` (depot-local, mutable).
"""
function raw_download_root()::String
    p = parse_optional_string(ENV_RAW_ROOT)
    p !== nothing && return p
    return Scratch.get_scratch!(parentmodule(@__MODULE__), "cloudbench_raw")
end

"""Parse `ENV[name]` as `Bool`; accept `1`, `true`, `yes`, `y`, `on` (case-insensitive)."""
function parse_bool_env(name::String, default::Bool)::Bool
    raw = strip(get(ENV, name, ""))
    isempty(raw) && return default
    return lowercase(raw) in ("1", "true", "yes", "y", "on")
end

end # module Config
