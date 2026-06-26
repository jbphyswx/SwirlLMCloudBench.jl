"""
    CaseDirs

Canonical local filesystem paths for CloudBench cases, combining [`Catalog`](@ref), [`Config`](@ref), and [`Paths`](@ref).

Paths use the **same bucket-shaped layout as downloads** — `[root]/[site_id]/[month]/[experiment-segment]/` — so a
[`Config.data_root`](@ref)-rooted mirror lines up with what `Simulation.download_cloudbench_raw!` writes under
[`Config.raw_download_root`](@ref). (This module does **not** use `Pkg.Artifacts`; CloudBench data is mirrored via a
mutable Scratch-backed cache — see the README for why.)
"""
module CaseDirs

using ..Catalog: Catalog
using ..Config: Config

export resolved_case_dir

"""
    resolved_case_dir(site_id, month, experiment; root=Config.data_root()) -> String

Canonical filesystem path for one CloudBench case, `[root]/[site_id]/[month]/[experiment-segment]/` (the published
bucket layout). `root` defaults to [`Config.data_root`](@ref) (env `SWIRL_LM_CLOUDBENCH_DATA_ROOT`).

- `site_id`: integer in `Catalog.CLOUDBENCH_CASE_INDICES`.
- `month`: integer in `Catalog.CLOUDBENCH_MONTHS`.
- `experiment`: `Symbol`, segment string (e.g. `"amip-p4k"`), or [`Catalog.CloudBenchExperiment`](@ref).

This is the same layout as `Simulation.local_simulation_dir(root, inst)`; use that when you already hold a
`CloudBenchInstance` / `CloudBenchSimulation`.
"""
function resolved_case_dir(
    site_id::Integer,
    month::Integer,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment};
    root::AbstractString = Config.data_root(),
)
    Catalog.valid_case_index(site_id) ||
        throw(ArgumentError("site_id must be in $(Catalog.CLOUDBENCH_CASE_INDICES), got $(site_id)"))
    Catalog.valid_month(month) ||
        throw(ArgumentError("month must be one of $(Catalog.CLOUDBENCH_MONTHS), got $(month)"))
    seg = Catalog.gcs_path_segment(experiment)  # validates Symbol experiments via parse_experiment
    return joinpath(String(root), string(Int(site_id)), string(Int(month)), seg)
end

end # module CaseDirs
