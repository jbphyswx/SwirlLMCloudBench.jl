using ..Catalog: Catalog

"""
    local_simulation_dir(root, inst::CloudBenchInstance) -> String

Local directory mirroring the public bucket layout
`[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/` (see the
[CloudBench README](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)).

Also accepts a [`CloudBenchSimulation`](@ref) (uses its catalog key).
"""
function local_simulation_dir(root::AbstractString, inst::CloudBenchInstance)
    seg = Catalog.gcs_path_segment(inst.experiment)
    return joinpath(String(root), string(inst.site_id), string(inst.month), seg)
end

local_simulation_dir(root::AbstractString, sim::CloudBenchSimulation) =
    local_simulation_dir(root, cloudbench_instance(sim))

"""Path to `sounding.csv` under `root` for this simulation."""
sounding_path(inst::CloudBenchInstance, root::AbstractString) =
    joinpath(local_simulation_dir(root, inst), "sounding.csv")

sounding_path(sim::CloudBenchSimulation, root::AbstractString) =
    sounding_path(cloudbench_instance(sim), root)

"""Path to `parameters.json` under `root` for this simulation."""
parameters_path(inst::CloudBenchInstance, root::AbstractString) =
    joinpath(local_simulation_dir(root, inst), "parameters.json")

parameters_path(sim::CloudBenchSimulation, root::AbstractString) =
    parameters_path(cloudbench_instance(sim), root)

"""Path to local `data.zarr` under `root` for this simulation (see [`open_zarr_local`](@ref))."""
zarr_local_path(inst::CloudBenchInstance, root::AbstractString) =
    joinpath(local_simulation_dir(root, inst), "data.zarr")

zarr_local_path(sim::CloudBenchSimulation, root::AbstractString) =
    zarr_local_path(cloudbench_instance(sim), root)
