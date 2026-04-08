"""
High-level path resolution combining `Catalog`, `Config`, and `Paths`.
"""
module Artifacts

using ..Catalog: Catalog
using ..Config: Config
using ..Paths: Paths

export resolved_case_dir

"""
    resolved_case_dir(experiment, case_index; month=nothing) -> String

Canonical filesystem path for one CloudBench case under the configured `data_root()`.

- `experiment`: `Symbol` or string accepted by `Catalog.parse_experiment`.
- `case_index`: integer in `Catalog.CLOUDBENCH_CASE_INDICES`.
- `month`: optional integer in `Catalog.CLOUDBENCH_MONTHS` for seasonal subfolders.
"""
function resolved_case_dir(experiment, case_index::Integer; month::Union{Nothing,Integer} = nothing)
    exp = Catalog.parse_experiment(experiment)
    Catalog.valid_case_index(case_index) ||
        throw(ArgumentError("case_index must be in $(Catalog.CLOUDBENCH_CASE_INDICES), got $(case_index)"))
    if month !== nothing
        Catalog.valid_month(month) ||
            throw(ArgumentError("month must be one of $(Catalog.CLOUDBENCH_MONTHS), got $(month)"))
    end
    return Paths.case_artifact_dir(Config.data_root(), exp, case_index; month)
end

end # module Artifacts
