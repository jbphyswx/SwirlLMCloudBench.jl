using InlineStrings: InlineStrings
using ..Catalog: Catalog

# --- Abstract hierarchy ---

"""Supertype for parsed identity + parameters/sounding slots (see [`CloudBenchMetadata`](@ref))."""
abstract type AbstractCloudBenchMetadata end

"""Supertype for how simulation **output** is accessed (remote Zarr, local mirror layout, etc.)."""
abstract type AbstractCloudBenchSimulation end

"""
    CloudBenchInstance(site_id, month, experiment)
    CloudBenchInstance(d::AbstractDict)

Immutable **catalog key** for one published CloudBench directory
`[SITE_ID]/[MONTH]/[EXPERIMENT]/` in the public bucket. No I/O and no output backend.

Use [`CloudBenchSimulation`](@ref) for the full object (metadata + output strategy).

`site_id` is in `0:499`, `month` in `Catalog.CLOUDBENCH_MONTHS`, and `experiment` is a [`Catalog.CloudBenchExperiment`](@ref)
or any input accepted by `Catalog.CloudBenchExperiment` (catalog `Symbol`, JSON/GCS-style string such as `"amip"` or `"amip-p4k"`).

`CloudBenchInstance` is `isbitstype` when `Int` is 64-bit (standard on supported Julia platforms).

`CloudBenchInstance(d)` requires keys `site_id`, `month`, and `experiment`.
"""
struct CloudBenchInstance
    site_id::Int
    month::Int
    experiment::Catalog.CloudBenchExperiment
    function CloudBenchInstance(site_id::Int, month::Int, experiment::Catalog.CloudBenchExperiment)
        Catalog.valid_case_index(site_id) || throw(ArgumentError("invalid site_id $(site_id)"))
        Catalog.valid_month(month) || throw(ArgumentError("invalid month $(month)"))
        return new(site_id, month, experiment)
    end
end

CloudBenchInstance(site_id::Int, month::Int, experiment::AbstractString) =
    CloudBenchInstance(site_id, month, Catalog.CloudBenchExperiment(experiment))

function CloudBenchInstance(site_id::Int, month::Int, experiment::Symbol)
    Catalog.parse_experiment(experiment)
    return CloudBenchInstance(site_id, month, Catalog.CloudBenchExperiment(experiment))
end

CloudBenchInstance(; site_id::Int, month::Int, experiment) = CloudBenchInstance(site_id, month, experiment)

function CloudBenchInstance(d::AbstractDict)
    haskey(d, "site_id") && haskey(d, "month") && haskey(d, "experiment") ||
        throw(ArgumentError("CloudBenchInstance dict requires keys: site_id, month, experiment"))
    return CloudBenchInstance(
        Int(d["site_id"]),
        Int(d["month"]),
        Catalog.CloudBenchExperiment(string(d["experiment"])),
    )
end

"""
    CloudBenchMetadata{P,S}

[`CloudBenchInstance`](@ref) plus **concrete** `parameters::P` and `sounding::S`. Use type parameters `Nothing` for a slot
with value `nothing` (no parsed object). Typical shapes:

- `CloudBenchMetadata{Nothing,Nothing}` — remote / catalog-only (see [`CloudBenchMetadataEmpty`](@ref)).
- `CloudBenchMetadata{CloudBenchParameters{Tf,Ss},CloudBenchSounding{Ts,V}}` — both files loaded from disk (defaults: `Tf=Float32`, `Ss=InlineStrings.String127` for parameters JSON; `Ts=Float32`, `V=Vector{Float32}` for sounding).

Other combinations (e.g. parameters-only) are valid if you construct them; there is no `Union` on the fields.
"""
struct CloudBenchMetadata{P<:Union{Nothing,CloudBenchParameters},S<:Union{Nothing,CloudBenchSounding}} <:
       AbstractCloudBenchMetadata
    instance::CloudBenchInstance
    parameters::P
    sounding::S
end

"""[`CloudBenchMetadata`](@ref)`{Nothing,Nothing}` — no parsed CSV/JSON."""
const CloudBenchMetadataEmpty = CloudBenchMetadata{Nothing,Nothing}

"""
    RemoteCloudBenchZarrOutput()

Output is read lazily from the public HTTPS `data.zarr` URL (see [`open_zarr`](@ref)). Carries no local path.
"""
struct RemoteCloudBenchZarrOutput <: AbstractCloudBenchSimulation end

"""
    LocalCloudBenchMirrorOutput(root)

Local filesystem layout `[root]/[SITE_ID]/[MONTH]/[EXPERIMENT]/` mirroring the bucket (see [`local_simulation_dir`](@ref)).
`root` is where raw downloads and optional local `data.zarr` live for this simulation’s tree.
"""
struct LocalCloudBenchMirrorOutput <: AbstractCloudBenchSimulation
    root::String
end

"""
    CloudBenchSimulation(metadata, output)
    CloudBenchSimulation(site_id, month, experiment)
    CloudBenchSimulation(d::AbstractDict)

Full **simulation** value: [`AbstractCloudBenchMetadata`](@ref) + [`AbstractCloudBenchSimulation`](@ref).

The common default `CloudBenchSimulation(site_id, month, experiment)` uses [`CloudBenchMetadataEmpty`](@ref) (`nothing`
for both parsed slots) and [`RemoteCloudBenchZarrOutput`](@ref) (stream remote Zarr; no local cache). Its static type is
[`CloudBenchSimulationRemote`](@ref).

To load parsed `parameters.json` / `sounding.csv` while keeping HTTPS Zarr, use [`load_cloudbench_simulation`](@ref)(...; `local_mirror=false`).
To load parsed files **and** record a local mirror root for [`open_zarr_local`](@ref), use [`load_cloudbench_simulation`](@ref)(...; `local_mirror=true`, the default).

# Property forwarding

For ergonomics, `site_id`, `month`, and `experiment` forward to `metadata.instance` (so `sim.site_id` works like the old API).
Parsed files and slots live on `metadata`: `sim.metadata.parameters`, `sim.metadata.sounding`. Use [`cloudbench_instance`](@ref) for the explicit catalog key.
"""
struct CloudBenchSimulation{M<:AbstractCloudBenchMetadata,O<:AbstractCloudBenchSimulation}
    metadata::M
    output::O
end

"""Default remote-only [`CloudBenchSimulation`](@ref) type (empty metadata + HTTPS Zarr output)."""
const CloudBenchSimulationRemote = CloudBenchSimulation{CloudBenchMetadataEmpty,RemoteCloudBenchZarrOutput}

"""[`CloudBenchSimulation`](@ref) with parsed parameters and [`CloudBenchSounding{Float32,Vector{Float32}}`](@ref) + [`LocalCloudBenchMirrorOutput`](@ref)."""
const CloudBenchSimulationLoaded = CloudBenchSimulation{
    CloudBenchMetadata{CloudBenchParameters{Float32,InlineStrings.String127},CloudBenchSounding{Float32,Vector{Float32}}},
    LocalCloudBenchMirrorOutput,
}

"""[`CloudBenchSimulation`](@ref) with parsed parameters and [`CloudBenchSounding{Float32,Vector{Float32}}`](@ref) + [`RemoteCloudBenchZarrOutput`](@ref) (HTTPS Zarr only)."""
const CloudBenchSimulationRemoteLoaded = CloudBenchSimulation{
    CloudBenchMetadata{CloudBenchParameters{Float32,InlineStrings.String127},CloudBenchSounding{Float32,Vector{Float32}}},
    RemoteCloudBenchZarrOutput,
}

function CloudBenchSimulation(site_id::Int, month::Int, experiment::AbstractString)
    inst = CloudBenchInstance(site_id, month, experiment)
    return CloudBenchSimulation(
        CloudBenchMetadata(inst, nothing, nothing),
        RemoteCloudBenchZarrOutput(),
    )
end

function CloudBenchSimulation(site_id::Int, month::Int, experiment::Catalog.CloudBenchExperiment)
    inst = CloudBenchInstance(site_id, month, experiment)
    return CloudBenchSimulation(
        CloudBenchMetadata(inst, nothing, nothing),
        RemoteCloudBenchZarrOutput(),
    )
end

function CloudBenchSimulation(site_id::Int, month::Int, experiment::Symbol)
    Catalog.parse_experiment(experiment)
    return CloudBenchSimulation(site_id, month, Catalog.CloudBenchExperiment(experiment))
end

function CloudBenchSimulation(d::AbstractDict)
    inst = CloudBenchInstance(d)
    return CloudBenchSimulation(CloudBenchMetadata(inst, nothing, nothing), RemoteCloudBenchZarrOutput())
end

"""Wrap an existing [`CloudBenchInstance`](@ref) as a remote-Zarr [`CloudBenchSimulation`](@ref) (no local metadata loaded)."""
function CloudBenchSimulation(inst::CloudBenchInstance)
    return CloudBenchSimulation(CloudBenchMetadata(inst, nothing, nothing), RemoteCloudBenchZarrOutput())
end

"""Extract the catalog key from a [`CloudBenchSimulation`](@ref)."""
cloudbench_instance(s::CloudBenchSimulation) = s.metadata.instance

function Base.getproperty(s::CloudBenchSimulation, sym::Symbol)
    sym === :metadata && return getfield(s, :metadata)
    sym === :output && return getfield(s, :output)
    return getproperty(cloudbench_instance(s), sym)
end

# Make the forwarded catalog-key fields discoverable (tab-completion / `propertynames`).
Base.propertynames(::CloudBenchSimulation, private::Bool = false) =
    (:metadata, :output, :site_id, :month, :experiment)

function Base.:(==)(a::CloudBenchMetadata, b::CloudBenchMetadata)
    typeof(a) === typeof(b) || return false
    return a.instance == b.instance && a.parameters == b.parameters && a.sounding == b.sounding
end

Base.:(==)(::RemoteCloudBenchZarrOutput, ::RemoteCloudBenchZarrOutput) = true

function Base.:(==)(a::LocalCloudBenchMirrorOutput, b::LocalCloudBenchMirrorOutput)
    return a.root == b.root
end

function Base.:(==)(a::CloudBenchSimulation, b::CloudBenchSimulation)
    typeof(a) === typeof(b) || return false
    return a.metadata == b.metadata && a.output == b.output
end

Base.:(==)(a::CloudBenchInstance, b::CloudBenchInstance) =
    a.site_id == b.site_id && a.month == b.month && a.experiment == b.experiment

# --- hash, consistent with the custom `==` above (so these are valid Dict/Set keys) ---
# Defaults are insufficient for the metadata/simulation chain because they contain a `CloudBenchSounding`
# (a struct of mutable `Vector`s), whose default object hash is identity-based; we hash by content via the
# `hash(::CloudBenchSounding, …)` method in sounding.jl. `nothing` slots and `String`/isbits fields hash fine.

Base.hash(x::CloudBenchInstance, h::UInt) =
    hash(x.experiment, hash(x.month, hash(x.site_id, hash(:CloudBenchInstance, h))))

Base.hash(m::CloudBenchMetadata, h::UInt) =
    hash(m.sounding, hash(m.parameters, hash(m.instance, hash(:CloudBenchMetadata, h))))

Base.hash(::RemoteCloudBenchZarrOutput, h::UInt) = hash(:RemoteCloudBenchZarrOutput, h)
Base.hash(o::LocalCloudBenchMirrorOutput, h::UInt) = hash(o.root, hash(:LocalCloudBenchMirrorOutput, h))

Base.hash(s::CloudBenchSimulation, h::UInt) =
    hash(getfield(s, :output), hash(getfield(s, :metadata), hash(:CloudBenchSimulation, h)))

# --- Compact display (avoid dumping large nested structs in the REPL) ---

function Base.show(io::IO, x::CloudBenchInstance)
    print(io, "CloudBenchInstance(", x.site_id, ", ", x.month, ", ")
    show(io, x.experiment)
    print(io, ")")
end

function Base.show(io::IO, ::RemoteCloudBenchZarrOutput)
    print(io, "RemoteCloudBenchZarrOutput()")
end

function Base.show(io::IO, o::LocalCloudBenchMirrorOutput)
    print(io, "LocalCloudBenchMirrorOutput(")
    show(io, o.root)
    print(io, ")")
end

function Base.show(io::IO, m::CloudBenchMetadata{P,S}) where {P,S}
    print(io, "CloudBenchMetadata(")
    show(io, m.instance)
    print(io, ", ")
    _show_cloudbench_slot(io, m.parameters)
    print(io, ", ")
    _show_cloudbench_slot(io, m.sounding)
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", m::CloudBenchMetadata{P,S}) where {P,S}
    println(io, "CloudBenchMetadata:")
    print(io, "  instance:    ")
    show(io, m.instance)
    println(io)
    print(io, "  parameters:  ")
    _show_cloudbench_slot(io, m.parameters)
    println(io)
    print(io, "  sounding:    ")
    _show_cloudbench_slot(io, m.sounding)
    println(io)
end

_show_cloudbench_slot(io, ::Nothing) = print(io, "(empty)")
_show_cloudbench_slot(io, x) = show(io, x)

function Base.show(io::IO, s::CloudBenchSimulation{M,O}) where {M,O}
    print(io, "CloudBenchSimulation(")
    show(io, s.metadata)
    print(io, ", ")
    show(io, s.output)
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", s::CloudBenchSimulation)
    println(io, typeof(s), ":")
    print(io, "  metadata:")
    println(io)
    print(io, "    instance:    ")
    show(io, s.metadata.instance)
    println(io)
    print(io, "    parameters:  ")
    _show_cloudbench_slot(io, s.metadata.parameters)
    println(io)
    print(io, "    sounding:    ")
    _show_cloudbench_slot(io, s.metadata.sounding)
    println(io)
    print(io, "  output:      ")
    show(io, s.output)
    println(io)
end
