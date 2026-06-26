using Documenter: Documenter
using SwirlLMCloudBench: SwirlLMCloudBench

Documenter.makedocs(;
    modules = [SwirlLMCloudBench],
    authors = "CliMA Contributors",
    sitename = "SwirlLMCloudBench.jl",
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    pages = [
        "Home" => "index.md",
        "API" => "api.md",
    ],
    # Many docstrings use `[...](@ref)` cross-links (incl. into not-yet-loaded extensions); warn rather than error
    # while the docs site matures, and don't require every docstring to be placed on a page.
    warnonly = true,
    checkdocs = :none,
)

Documenter.deploydocs(;
    repo = "github.com/jbphyswx/SwirlLMCloudBench.jl",
    devbranch = "main",
    push_preview = true,
)
