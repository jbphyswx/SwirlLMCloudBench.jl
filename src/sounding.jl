using CSV: CSV

"""
    CloudBenchSounding{T<:AbstractFloat,V<:AbstractVector{T}}

Atmospheric column from CloudBench `sounding.csv`: `z`, `temperature`, `q_t`, `u`, `v`, `rho` (same columns as the public CSV).

All six columns share one **vector type** `V` (e.g. `Vector{Float32}` from disk, or `StaticArrays.SVector{n,Float32}` for fixed size).

When loading from a path, the default is `T = Float32` and `V = Vector{T}` (see [`read_cloudbench_sounding_columns`](@ref) and
[`CloudBenchSounding(::AbstractString)`](@ref)).

    CloudBenchSounding{T,V}(z, temperature, q_t, u, v, rho)

Construct from six vectors of the **same** type `V<:AbstractVector{T}`; lengths must match.
"""
struct CloudBenchSounding{T<:AbstractFloat,V<:AbstractVector{T}}
    z::V
    temperature::V
    q_t::V
    u::V
    v::V
    rho::V
    function CloudBenchSounding{T,V}(z::V, temperature::V, q_t::V, u::V, v::V, rho::V) where {T<:AbstractFloat,V<:AbstractVector{T}}
        n = length(z)
        if !(length(temperature) == n && length(q_t) == n && length(u) == n && length(v) == n && length(rho) == n)
            throw(
                DimensionMismatch(
                    "all sounding columns must have the same length (got $(length(z)), $(length(temperature)), $(length(q_t)), $(length(u)), $(length(v)), $(length(rho)))",
                ),
            )
        end
        return new{T,V}(z, temperature, q_t, u, v, rho)
    end
end

"""
    CloudBenchSounding(path; eltype=Float32) -> CloudBenchSounding{eltype,Vector{eltype}}

Parse `sounding.csv` at `path`. Keyword `eltype` sets the storage scalar type (default `Float32`); columns are stored as
`Vector{eltype}`.
"""
function CloudBenchSounding(path::AbstractString; eltype::Type{<:AbstractFloat}=Float32)
    z, temperature, q_t, u, v, rho = read_cloudbench_sounding_columns(path, eltype)
    return CloudBenchSounding{eltype,Vector{eltype}}(z, temperature, q_t, u, v, rho)
end

"""
    read_cloudbench_sounding_columns(path, eltype::Type{<:AbstractFloat}=Float32)

Read the six CloudBench sounding columns from `sounding.csv` as `Vector{eltype}` values
`(z, temperature, q_t, u, v, rho)` without constructing [`CloudBenchSounding`](@ref).
"""
function read_cloudbench_sounding_columns(path::AbstractString, eltype::Type{<:AbstractFloat}=Float32)
    F = eltype
    f = CSV.File(path; types=Dict(:z => F, :temperature => F, :q_t => F, :u => F, :v => F, :rho => F))
    z = collect(f.z)
    temperature = collect(f.temperature)
    q_t = collect(f.q_t)
    u = collect(f.u)
    v = collect(f.v)
    rho = collect(f.rho)
    return z, temperature, q_t, u, v, rho
end

function Base.show(io::IO, s::CloudBenchSounding)
    n = length(s.z)
    print(io, "CloudBenchSounding(", n, " vertical level", n == 1 ? "" : "s", ")")
end
