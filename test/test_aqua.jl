using SwirlLMCloudBench: SwirlLMCloudBench
using Aqua: Aqua
using Test: @testset

@testset "Aqua.jl" begin
    Aqua.test_all(
        SwirlLMCloudBench;
        ambiguities = true,
        unbound_args = true,
        undefined_exports = true,
        project_extras = true,
        stale_deps = true,
        deps_compat = true,
        persistent_tasks = false,
    )
end
