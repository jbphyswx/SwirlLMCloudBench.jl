using ..Catalog: Catalog

const GCS_SIMULATION_OUTPUT_BASE = "https://storage.googleapis.com/cloudbench-simulation-output"

"""
    _cloudbench_object_url(site_id, month, experiment, basename) -> String

Internal: HTTPS URL for object `basename` under the public `cloudbench-simulation-output` layout
`[base]/[site_id]/[month]/[experiment-segment]/[basename]`. `experiment` may be a catalog `Symbol` (validated),
a segment string (e.g. `"amip-p4k"`), or [`Catalog.CloudBenchExperiment`](@ref) — all handled by
[`Catalog.gcs_path_segment`](@ref).
"""
function _cloudbench_object_url(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment},
    basename::AbstractString,
)
    Catalog.valid_case_index(site_id) || throw(ArgumentError("invalid site_id $(site_id)"))
    Catalog.valid_month(month) || throw(ArgumentError("invalid month $(month)"))
    seg = Catalog.gcs_path_segment(experiment)
    return join([GCS_SIMULATION_OUTPUT_BASE, string(site_id), string(month), seg, basename], '/')
end

"""
    cloudbench_sounding_url(sim) -> String
    cloudbench_sounding_url(site_id, month, experiment) -> String

HTTPS URL for CloudBench `sounding.csv` under the public simulation-output layout.
`experiment` is a catalog `Symbol`, a segment string (e.g. `"amip-p4k"`), or [`Catalog.CloudBenchExperiment`](@ref).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).
"""
cloudbench_sounding_url(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment},
) = _cloudbench_object_url(site_id, month, experiment, "sounding.csv")

cloudbench_sounding_url(inst::CloudBenchInstance) =
    cloudbench_sounding_url(inst.site_id, inst.month, inst.experiment)

cloudbench_sounding_url(sim::CloudBenchSimulation) = cloudbench_sounding_url(cloudbench_instance(sim))

"""
    cloudbench_zarr_url(sim) -> String
    cloudbench_zarr_url(site_id, month, experiment) -> String

HTTPS URL for the public `data.zarr` store (open lazily with [`open_zarr`](@ref)).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).
"""
cloudbench_zarr_url(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment},
) = _cloudbench_object_url(site_id, month, experiment, "data.zarr")

cloudbench_zarr_url(inst::CloudBenchInstance) = cloudbench_zarr_url(inst.site_id, inst.month, inst.experiment)

cloudbench_zarr_url(sim::CloudBenchSimulation) = cloudbench_zarr_url(cloudbench_instance(sim))

"""
    cloudbench_parameters_url(sim) -> String
    cloudbench_parameters_url(site_id, month, experiment) -> String

HTTPS URL for CloudBench `parameters.json` (same path prefix as `sounding.csv` / `data.zarr`).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).
"""
cloudbench_parameters_url(
    site_id::Int,
    month::Int,
    experiment::Union{Symbol,AbstractString,Catalog.CloudBenchExperiment},
) = _cloudbench_object_url(site_id, month, experiment, "parameters.json")

cloudbench_parameters_url(inst::CloudBenchInstance) =
    cloudbench_parameters_url(inst.site_id, inst.month, inst.experiment)

cloudbench_parameters_url(sim::CloudBenchSimulation) = cloudbench_parameters_url(cloudbench_instance(sim))

"""
    cloudbench_urls(sim) -> NamedTuple
    cloudbench_urls(site_id, month, experiment) -> NamedTuple

HTTPS URLs for CloudBench `sounding.csv`, `parameters.json`, and `data.zarr` (same path prefix).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref).
"""
cloudbench_urls(sim::CloudBenchSimulation) = (
    sounding = cloudbench_sounding_url(sim),
    parameters = cloudbench_parameters_url(sim),
    zarr = cloudbench_zarr_url(sim),
)
