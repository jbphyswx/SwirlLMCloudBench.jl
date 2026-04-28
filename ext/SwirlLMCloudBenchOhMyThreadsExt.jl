"""
    SwirlLMCloudBenchOhMyThreadsExt

Loads when `OhMyThreads` is available. Defines [`SwirlLMCloudBench.cloudbench_tmap`](@ref).
"""
module SwirlLMCloudBenchOhMyThreadsExt

using OhMyThreads: OhMyThreads
using SwirlLMCloudBench: SwirlLMCloudBench

"""Threaded `map` via OhMyThreads (each element of `collection` is passed to `f`)."""
function SwirlLMCloudBench.cloudbench_tmap(f, collection)
    return OhMyThreads.tmap(f, collection)
end

end
