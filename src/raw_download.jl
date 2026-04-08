import InlineStrings
using Downloads: Downloads
using ..Config: Config

"""
    download_cloudbench_raw!(sim; root=nothing, sounding=true, parameters=true, zarr=false) -> String

Download raw bucket files into `[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/`, mirroring the public layout.
When `root === nothing`, uses [`raw_download_root`](@ref).

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref) (the catalog key is used).

Skips a file if it already exists. Keep `zarr=false`; downloading the full `data.zarr` tree is not supported — use [`open_zarr`](@ref) for remote lazy access.

Returns the simulation directory ([`local_simulation_dir`](@ref)(`root`, `sim`)).

`verbose` controls download messages for this call only (`nothing` → [`cloudbench_logging`](@ref)).
"""
function download_cloudbench_raw!(
    inst::CloudBenchInstance;
    root::Union{Nothing,AbstractString} = nothing,
    sounding::Bool = true,
    parameters::Bool = true,
    zarr::Bool = false,
    verbose::Union{Nothing,Bool} = nothing,
)
    zarr && throw(ArgumentError("mirroring data.zarr is not implemented; use open_zarr(sim) for HTTPS lazy access"))
    r = root === nothing ? Config.raw_download_root() : String(normpath(expanduser(String(root))))
    dir = local_simulation_dir(r, inst)
    mkpath(dir)
    if sounding
        dest = sounding_path(inst, r)
        if !isfile(dest)
            url = cloudbench_sounding_url(inst)
            _Pkg.cloudbench_info("Downloading CloudBench sounding.csv"; verbose, url, dest)
            Downloads.download(url, dest)
        end
    end
    if parameters
        dest = parameters_path(inst, r)
        if !isfile(dest)
            url = cloudbench_parameters_url(inst)
            _Pkg.cloudbench_info("Downloading CloudBench parameters.json"; verbose, url, dest)
            Downloads.download(url, dest)
        end
    end
    return dir
end

function download_cloudbench_raw!(
    sim::CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    kwargs...,
)
    return download_cloudbench_raw!(cloudbench_instance(sim); root, kwargs...)
end

"""Load [`CloudBenchSounding`](@ref) from [`sounding_path`](@ref)(`inst`, `root`) (file must exist)."""
function load_cloudbench_sounding(
    inst::CloudBenchInstance,
    root::AbstractString;
    eltype::Type{<:AbstractFloat}=Float32,
)
    return CloudBenchSounding(sounding_path(inst, root); eltype)
end

load_cloudbench_sounding(sim::CloudBenchSimulation, root::AbstractString; kwargs...) =
    load_cloudbench_sounding(cloudbench_instance(sim), root; kwargs...)

"""
    load_cloudbench_simulation(inst; root=nothing, download=true, local_mirror=true, verbose=nothing) -> CloudBenchSimulation

Build a [`CloudBenchSimulation`](@ref) with [`CloudBenchMetadata`](@ref) (parsed `parameters.json` and `sounding.csv`).

- **`local_mirror=true`** (default): also set [`LocalCloudBenchMirrorOutput`](@ref)(`root`) so [`open_zarr_local`](@ref) can use that tree.
- **`local_mirror=false`**: set [`RemoteCloudBenchZarrOutput`](@ref) instead — metadata is still read from disk under `root`, but Zarr stays remote ([`open_zarr`](@ref)).

When `download`, calls [`download_cloudbench_raw!`](@ref)(`inst`; `root`, `verbose`). `root === nothing` uses [`raw_download_root`](@ref).

Keyword `sounding_eltype` (default `Float32`) is forwarded to [`CloudBenchSounding`](@ref) when parsing `sounding.csv`.

Keywords `parameters_float` (default `Float32`) and `parameters_string` (default `InlineStrings.String127`) are forwarded to
[`read_cloudbench_parameters`](@ref) when parsing `parameters.json`.

`sim` may be a [`CloudBenchInstance`](@ref) or [`CloudBenchSimulation`](@ref) (catalog key only).

For a lightweight simulation with empty metadata, use [`CloudBenchSimulation`](@ref)(`site_id`, `month`, `experiment`).
"""
function load_cloudbench_simulation(
    inst::CloudBenchInstance;
    root::Union{Nothing,AbstractString} = nothing,
    download::Bool = true,
    local_mirror::Bool = true,
    sounding_eltype::Type{<:AbstractFloat}=Float32,
    parameters_float::Type{<:AbstractFloat}=Float32,
    parameters_string::Type{<:AbstractString}=InlineStrings.String127,
    verbose::Union{Nothing,Bool} = nothing,
)
    r = root === nothing ? Config.raw_download_root() : String(normpath(expanduser(String(root))))
    download && download_cloudbench_raw!(inst; root = r, verbose = verbose)
    ppath = parameters_path(inst, r)
    spath = sounding_path(inst, r)
    isfile(ppath) ||
        error("missing parameters.json at $(ppath); run download_cloudbench_raw!(inst) or pass the correct root=")
    isfile(spath) ||
        error("missing sounding.csv at $(spath); run download_cloudbench_raw!(inst) or pass the correct root=")
    meta = CloudBenchMetadata(
        inst,
        read_cloudbench_parameters(
            ppath;
            float_type=parameters_float,
            string_type=parameters_string,
        ),
        CloudBenchSounding(spath; eltype=sounding_eltype),
    )
    out = local_mirror ? LocalCloudBenchMirrorOutput(r) : RemoteCloudBenchZarrOutput()
    return CloudBenchSimulation(meta, out)
end

function load_cloudbench_simulation(
    sim::CloudBenchSimulation;
    root::Union{Nothing,AbstractString} = nothing,
    kwargs...,
)
    return load_cloudbench_simulation(cloudbench_instance(sim); root, kwargs...)
end
