"""
    SwirlLMCloudBenchOhMyThreadsExt

Loads when `OhMyThreads` is available. Defines [`SwirlLMCloudBench.cloudbench_tmap`](@ref).
"""
module SwirlLMCloudBenchOhMyThreadsExt

using OhMyThreads: OhMyThreads
using SwirlLMCloudBench: SwirlLMCloudBench

"""
    cloudbench_tmap(f, collection; kwargs...)

Threaded `map` via `OhMyThreads.tmap` (each element of `collection` is passed to `f`). Extra keyword arguments
(e.g. `scheduler`, `ntasks`, `chunksize`) are forwarded to `OhMyThreads.tmap`.
"""
function SwirlLMCloudBench.cloudbench_tmap(f, collection; kwargs...)
    return OhMyThreads.tmap(f, collection; kwargs...)
end

end
