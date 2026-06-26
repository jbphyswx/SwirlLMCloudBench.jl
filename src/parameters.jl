using InlineStrings: InlineStrings
using JSON: JSON

"""
    CloudBenchParameters{T<:AbstractFloat,S<:AbstractString}

Parsed `parameters.json` from a CloudBench simulation directory (see upstream variable table / metadata in the
[CloudBench README](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)).

Floating-point fields use scalar type `T` (default `Float32`). String fields (`experiment`, `sounding_path`, `config_path`)
share type `S` (default `InlineStrings.String127`, so the struct is `isbits`). `sounding_path` / `config_path` are the
upstream absolute paths in Google's **static** CloudBench layout — at most ~94 chars, well within 127. Pass
`string_type = String` for heap strings only if you parse some other `parameters.json` with longer paths.

[`CloudBenchParameters`](@ref)(`d`) and [`read_cloudbench_parameters`](@ref) default to `T = Float32`, `S = InlineStrings.String127`.

Unknown keys in the JSON object raise `ArgumentError` by default (`strict=true`); pass `strict=false` to ignore them with a `@warn`.

# Example

```julia
CloudBenchParameters(dict)                                  # Float32 + InlineStrings.String127 (isbits, default)
CloudBenchParameters{Float64,String}(dict)                  # JSON-like doubles + heap strings
```
"""
struct CloudBenchParameters{T<:AbstractFloat,S<:AbstractString}
    experiment::S
    month::Int
    latitude::T
    longitude::T
    sst::T
    p_sfc::T
    theta_li_sfc::T
    q_t_sfc::T
    zenith::T
    insolation::T
    irrad::T
    sounding_path::S
    config_path::S
end

"""Default `parameters.json` parse type: [`CloudBenchParameters`](@ref)`{Float32,InlineStrings.String127}` (`isbits`)."""
const CloudBenchParametersDefault = CloudBenchParameters{Float32,InlineStrings.String127}

function _as_float(::Type{T}, x)::T where {T<:AbstractFloat}
    x isa Integer && return T(x)
    x isa AbstractFloat && return T(x)
    return T(Float64(x))
end

function _as_int(x)::Int
    x isa Integer && return Int(x)
    return Int(round(Float64(x)))
end

function _as_string(::Type{S}, x)::S where {S<:AbstractString}
    s = String(x)
    if S === String
        return s
    end
    return S(s)::S
end

"""
    CloudBenchParameters(d::AbstractDict; strict=true)

Equivalent to `CloudBenchParameters{Float32,InlineStrings.String127}(d; strict)`.
"""
CloudBenchParameters(d::AbstractDict; strict::Bool = true) =
    CloudBenchParameters{Float32,InlineStrings.String127}(d; strict = strict)

"""
    CloudBenchParameters{T,S}(d::AbstractDict; strict=true)

Build from a `Dict{String,Any}`-like object (e.g. `JSON.parse` output). Requires all known keys. With `strict=true`
(default) any **extra** key raises `ArgumentError`; with `strict=false` extra keys are ignored with a `@warn`
(forward-compatible with upstream schema additions).
"""
function CloudBenchParameters{T,S}(d::AbstractDict; strict::Bool = true) where {T<:AbstractFloat,S<:AbstractString}
    d = Dict{String,Any}(d)
    function popreq!(k::AbstractString, conv)
        haskey(d, k) || error("CloudBenchParameters: missing key $(repr(k)) in parameters.json")
        return conv(pop!(d, k))
    end
    experiment = popreq!("experiment", x -> _as_string(S, x))
    month = popreq!("month", _as_int)
    latitude = popreq!("latitude", x -> _as_float(T, x))
    longitude = popreq!("longitude", x -> _as_float(T, x))
    sst = popreq!("sst", x -> _as_float(T, x))
    p_sfc = popreq!("p_sfc", x -> _as_float(T, x))
    theta_li_sfc = popreq!("theta_li_sfc", x -> _as_float(T, x))
    q_t_sfc = popreq!("q_t_sfc", x -> _as_float(T, x))
    zenith = popreq!("zenith", x -> _as_float(T, x))
    insolation = popreq!("insolation", x -> _as_float(T, x))
    irrad = popreq!("irrad", x -> _as_float(T, x))
    sounding_path = popreq!("sounding_path", x -> _as_string(S, x))
    config_path = popreq!("config_path", x -> _as_string(S, x))
    if !isempty(d)
        msg = "CloudBenchParameters: unknown keys in parameters.json: $(repr(collect(keys(d))))"
        strict ? throw(ArgumentError(msg)) : @warn(msg)
    end
    return CloudBenchParameters{T,S}(
        experiment,
        month,
        latitude,
        longitude,
        sst,
        p_sfc,
        theta_li_sfc,
        q_t_sfc,
        zenith,
        insolation,
        irrad,
        sounding_path,
        config_path,
    )
end

"""Read and parse `parameters.json` from disk (`T = Float32`, `S = InlineStrings.String127` by default; `strict` per [`CloudBenchParameters`](@ref))."""
function read_cloudbench_parameters(
    path::AbstractString;
    float_type::Type{<:AbstractFloat}=Float32,
    string_type::Type{<:AbstractString}=InlineStrings.String127,
    strict::Bool = true,
)
    return CloudBenchParameters{float_type,string_type}(JSON.parsefile(path); strict = strict)
end

"""Parse `parameters.json` from a JSON string (`T = Float32`, `S = InlineStrings.String127` by default; `strict` per [`CloudBenchParameters`](@ref))."""
function parse_cloudbench_parameters(
    json::AbstractString;
    float_type::Type{<:AbstractFloat}=Float32,
    string_type::Type{<:AbstractString}=InlineStrings.String127,
    strict::Bool = true,
)
    return CloudBenchParameters{float_type,string_type}(JSON.parse(json); strict = strict)
end

function Base.show(io::IO, p::CloudBenchParameters)
    print(io, "CloudBenchParameters(")
    show(io, p.experiment)
    print(io, ", month=", p.month, ", lat=", p.latitude, ", lon=", p.longitude, ", …)")
end
