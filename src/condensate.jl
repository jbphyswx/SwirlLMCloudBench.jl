"""
    split_q_c(q_c, T; backend = DefaultThermodynamicsBackend()) -> (q_liq, q_ice)

Given condensed-phase specific humidity `q_c` (kg/kg) from CloudBench `data.zarr` and air temperature `T` (K),
return `(q_liq, q_ice)` by apportioning `q_c` with [`liquid_fraction`](@ref).

Two methods:

- **Scalars** `split_q_c(q_c::Real, T::Real)` — `q_c` and `T` may have different scalar types (they are promoted);
  returns a `Tuple` of two scalars.
- **Arrays** `split_q_c(q_c::AbstractArray, T::AbstractArray)` — same `axes` required; returns `(q_liq, q_ice)` as
  two arrays. This is the natural form for whole `data.zarr` fields: `q_liq, q_ice = split_q_c(q_c, T)`.
  (Element-wise broadcasting `split_q_c.(q_c, T)` instead yields an array of tuples.)

The published variable table lists `q_c` as condensed-phase specific humidity; it also lists separate hydrometeors
such as `q_r` and `q_s` — this function only splits **`q_c`**, not rain or snow.
"""
@inline function split_q_c(q_c::Real, T::Real; backend = DefaultThermodynamicsBackend())
    FT = float(promote_type(typeof(q_c), typeof(T)))
    fl = liquid_fraction(backend, FT(T))
    qc = FT(q_c)
    return (; q_liq = qc * fl, q_ice = qc * (one(FT) - fl))
end

function split_q_c(q_c::AbstractArray, T::AbstractArray; backend = DefaultThermodynamicsBackend())
    axes(q_c) == axes(T) ||
        throw(DimensionMismatch("q_c and T must have the same axes; got $(axes(q_c)) and $(axes(T))"))
    f = liquid_fraction.(backend, float.(T))
    q_liq = q_c .* f
    q_ice = q_c .* (1 .- f)
    return (; q_liq, q_ice)
end
