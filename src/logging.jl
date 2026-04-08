using Logging: Logging

const _cloudbench_logging_enabled = Ref(false)

function __init__()
    v = strip(get(ENV, "SWIRL_LM_CLOUDBENCH_LOGGING", ""))
    if v in ("1", "true", "TRUE", "yes", "YES")
        _cloudbench_logging_enabled[] = true
    end
    return nothing
end

"""
    cloudbench_logging() -> Bool

Whether this package emits optional informational messages (downloads, Zarr opens, NetCDF writes) when a call uses
`verbose=nothing`. Default: `false`.

Set [`cloudbench_logging!`](@ref) or environment variable `SWIRL_LM_CLOUDBENCH_LOGGING` (`1`, `true`, or `yes`) before
`using SwirlLMCloudBench` if you want that default on when the package loads. Many functions also accept
`verbose::Union{Nothing,Bool}=nothing`: `true` / `false` overrides the global default for that call only.
"""
cloudbench_logging() = _cloudbench_logging_enabled[]

"""
    cloudbench_logging!(enable::Bool) -> enable

Turn optional package informational logging on or off at runtime.
"""
function cloudbench_logging!(enable::Bool)
    _cloudbench_logging_enabled[] = enable
    return enable
end

"""
    cloudbench_info(message; verbose=nothing, kwargs...)

Emit `message` at the info level with `kwargs` as log properties when logging is on for this call:

- `verbose === nothing` — use [`cloudbench_logging`](@ref) (global / `ENV` default).
- `verbose === true` or `false` — override the global setting **for this message only**.

Used internally and by extensions; extenders may call this for consistent behavior.
"""
function cloudbench_info(msg::AbstractString; verbose::Union{Nothing,Bool} = nothing, kwargs...)
    on = verbose === nothing ? _cloudbench_logging_enabled[] : verbose
    on || return nothing
    Logging.@info msg (; kwargs...)
    return nothing
end
