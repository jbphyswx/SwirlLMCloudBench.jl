using InlineStrings: InlineStrings
using JSON: JSON

"""
    CloudBenchParameters{T<:AbstractFloat,S<:AbstractString}

Parsed `parameters.json` from a CloudBench simulation directory (see upstream variable table / metadata in the
[CloudBench README](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)).

Floating-point fields use scalar type `T` (default `Float32`). String fields (`experiment`, `sounding_path`, `config_path`)
share type `S` (default `InlineStrings.String127` for `isbits` storage when `S` is an inline type).

`sounding_path` and `config_path` are **upstream absolute paths** inside Google’s layout, not your local mirror.

[`CloudBenchParameters`](@ref)(`d`) and [`read_cloudbench_parameters`](@ref) default to `T = Float32`, `S = InlineStrings.String127`.
Use [`CloudBenchParameters{T,S}(d)`](@ref) or keyword `string_type = String` if a path can exceed the inline capacity.

Unknown keys in the JSON object are an error (strict schema).

# Example

```julia
CloudBenchParameters(dict)                    # Float32 + InlineStrings.String127
CloudBenchParameters{Float64,String}(dict)    # JSON-like doubles + heap strings
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

"""Default `parameters.json` parse: [`CloudBenchParameters`](@ref)`{Float32,InlineStrings.String127}`."""
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
    CloudBenchParameters(d::AbstractDict)

Equivalent to `CloudBenchParameters{Float32,InlineStrings.String127}(d)`.
"""
CloudBenchParameters(d::AbstractDict) = CloudBenchParameters{Float32,InlineStrings.String127}(d)

"""
    CloudBenchParameters{T,S}(d::AbstractDict)

Build from a `Dict{String,Any}`-like object (e.g. `JSON.parse` output). Requires exactly the known keys; any extra key
raises `ArgumentError`.
"""
function CloudBenchParameters{T,S}(d::AbstractDict) where {T<:AbstractFloat,S<:AbstractString}
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
    isempty(d) || throw(
        ArgumentError(
            "CloudBenchParameters: unknown keys in parameters.json: $(repr(collect(keys(d))))",
        ),
    )
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

"""Read and parse `parameters.json` from disk (`T = Float32`, `S = InlineStrings.String127` by default)."""
function read_cloudbench_parameters(
    path::AbstractString;
    float_type::Type{<:AbstractFloat}=Float32,
    string_type::Type{<:AbstractString}=InlineStrings.String127,
)
    return CloudBenchParameters{float_type,string_type}(JSON.parsefile(path))
end

"""Parse `parameters.json` from a JSON string (`T = Float32`, `S = InlineStrings.String127` by default)."""
function parse_cloudbench_parameters(
    json::AbstractString;
    float_type::Type{<:AbstractFloat}=Float32,
    string_type::Type{<:AbstractString}=InlineStrings.String127,
)
    return CloudBenchParameters{float_type,string_type}(JSON.parse(json))
end

function Base.show(io::IO, p::CloudBenchParameters)
    print(io, "CloudBenchParameters(")
    show(io, p.experiment)
    print(io, ", month=", p.month, ", lat=", p.latitude, ", lon=", p.longitude, ", …)")
end
