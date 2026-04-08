"""
Static catalog of SwirlLM CloudBench dimensions: ensemble indices, months, and experiment IDs.

These match the public CloudBench description in Swirl-LM
([cloud_feedback README](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)).
Callers should treat this module as the single source of truth for valid labels in Julia workflows.
"""
module Catalog

export CLOUDBENCH_CASE_INDICES,
    CLOUDBENCH_MONTHS,
    EXPERIMENTS,
    CloudBenchExperiment,
    experiment_names,
    parse_experiment,
    gcs_path_segment,
    valid_case_index,
    valid_month,
    n_cases

"""Inclusive range of ensemble member indices (0–499)."""
const CLOUDBENCH_CASE_INDICES = 0:499

"""Calendar months used in the published CloudBench seasonal sampling (Jan, Apr, Jul, Oct)."""
const CLOUDBENCH_MONTHS = (1, 4, 7, 10)

"""
Experiment identifiers aligned with the upstream naming convention.

Extend this tuple when new experiment IDs are published; keep order stable for reproducible manifests.
"""
const EXPERIMENTS = (:amip, :amip_p4k, :amip_4xco2, :amip_p4k_2xco2, :amip_p4k_4xco2)

"""
    CloudBenchExperiment

`UInt8`-backed enum of published CloudBench experiments. Values match `EXPERIMENTS` order (`Integer` / index `1:length(EXPERIMENTS)`).

Construct via `CloudBenchExperiment(:amip)`, `CloudBenchExperiment(\"amip-p4k\")`, or use `Catalog.amip`, etc.
"""
@enum CloudBenchExperiment::UInt8 begin
    amip = 1
    amip_p4k = 2
    amip_4xco2 = 3
    amip_p4k_2xco2 = 4
    amip_p4k_4xco2 = 5
end

function Base.Symbol(e::CloudBenchExperiment)
    return EXPERIMENTS[Int(e)]
end

function CloudBenchExperiment(sym::Symbol)
    parse_experiment(sym)
    i = findfirst(==(sym), EXPERIMENTS)::Int
    return CloudBenchExperiment(i)
end

function CloudBenchExperiment(name::AbstractString)
    s = lowercase(strip(String(name)))
    s = replace(s, '-' => '_')
    return CloudBenchExperiment(Symbol(s))
end

let _vals = (amip, amip_p4k, amip_4xco2, amip_p4k_2xco2, amip_p4k_4xco2)
    @assert length(_vals) == length(EXPERIMENTS)
    for ev in _vals
        @assert EXPERIMENTS[Int(ev)] === Symbol(ev)
    end
end

function Base.show(io::IO, e::CloudBenchExperiment)
    show(io, Symbol(e))
end

"""Number of ensemble members (`length(CLOUDBENCH_CASE_INDICES)`)."""
n_cases() = length(CLOUDBENCH_CASE_INDICES)

"""`Vector{Symbol}` of experiment names (copy)."""
experiment_names() = collect(EXPERIMENTS)

"""
    parse_experiment(name) -> Symbol

Parse `name` (string or symbol) to a canonical `Symbol`, or throw `ArgumentError`.
"""
function parse_experiment(name::Symbol)
    name in EXPERIMENTS || throw(ArgumentError("Unknown CloudBench experiment: $(repr(name)). Expected one of $(EXPERIMENTS)."))
    return name
end

parse_experiment(name::AbstractString) = parse_experiment(Symbol(lowercase(strip(name))))

"""Return `true` if `i` is a valid CloudBench case index."""
valid_case_index(i::Integer) = i in CLOUDBENCH_CASE_INDICES

"""Return `true` if `m` is a valid CloudBench calendar month label in this catalog."""
valid_month(m::Integer) = m in CLOUDBENCH_MONTHS

"""
    gcs_path_segment(experiment::Symbol) -> String

CloudBench GCS URL segment for `experiment` (e.g. `:amip_p4k` → `\"amip-p4k\"`), matching
`cloudbench-simulation-output` layout used by sounding CSV and Zarr stores.
"""
function gcs_path_segment(exp::Symbol)
    parse_experiment(exp)
    return replace(String(exp), '_' => '-')
end

function gcs_path_segment(exp::CloudBenchExperiment)
    return replace(String(Symbol(exp)), '_' => '-')
end

"""Path segment from a string like `\"amip\"` or `\"amip-p4k\"` (normalized to hyphenated form)."""
function gcs_path_segment(exp::AbstractString)
    s = lowercase(strip(String(exp)))
    return replace(s, '_' => '-')
end

end # module Catalog
