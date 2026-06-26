"""Lower temperature (K) of the Swirl-LM CloudBench liquid-fraction ramp: at or below this, all condensate is ice."""
const CONDENSATE_T_ICENUC = 233.0

"""Upper temperature (K) of the ramp: at or above this, all condensate is liquid."""
const CONDENSATE_T_FREEZE = 273.15

"""
    condensate_liquid_fraction(T) -> Real

Linear liquid fraction used in Swirl-LM CloudBench post-processing:

``f_l = \\mathrm{clamp}((T - 233\\,\\mathrm{K})/(273.15\\,\\mathrm{K} - 233\\,\\mathrm{K}), 0, 1)``

(thresholds [`CONDENSATE_T_ICENUC`](@ref) / [`CONDENSATE_T_FREEZE`](@ref)).

At `T ≤ 233 K` all condensate is treated as ice; at `T ≥ 273.15 K` as liquid.
Documented with the [CloudBench dataset](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md).
"""
@inline function condensate_liquid_fraction(T::Real)
    FT = float(typeof(T))
    f_l = (FT(T) - FT(CONDENSATE_T_ICENUC)) / (FT(CONDENSATE_T_FREEZE) - FT(CONDENSATE_T_ICENUC))
    return clamp(f_l, zero(FT), one(FT))
end

"""
    split_q_c(q_c, T) -> (q_liq, q_ice)

Given condensed-phase specific humidity `q_c` (kg/kg) from CloudBench `data.zarr` and air temperature `T` (K),
return `(q_liq, q_ice)` by apportioning `q_c` with [`condensate_liquid_fraction`](@ref).

Two methods:

- **Scalars** `split_q_c(q_c::Real, T::Real)` — `q_c` and `T` may have different scalar types (they are promoted);
  returns a `Tuple` of two scalars.
- **Arrays** `split_q_c(q_c::AbstractArray, T::AbstractArray)` — same `axes` required; returns `(q_liq, q_ice)` as
  two arrays. This is the natural form for whole `data.zarr` fields: `q_liq, q_ice = split_q_c(q_c, T)`.
  (Element-wise broadcasting `split_q_c.(q_c, T)` instead yields an array of tuples.)

The published variable table lists `q_c` as condensed-phase specific humidity; it also lists separate hydrometeors
such as `q_r` and `q_s` — this function only splits **`q_c`**, not rain or snow.
"""
@inline function split_q_c(q_c::Real, T::Real)
    f = condensate_liquid_fraction(T)
    FT = promote_type(typeof(q_c), typeof(f))
    qc = FT(q_c)
    fl = FT(f)
    return qc * fl, qc * (one(FT) - fl)
end

function split_q_c(q_c::AbstractArray, T::AbstractArray)
    axes(q_c) == axes(T) ||
        throw(DimensionMismatch("q_c and T must have the same axes; got $(axes(q_c)) and $(axes(T))"))
    f = condensate_liquid_fraction.(T)
    q_liq = q_c .* f
    q_ice = q_c .* (1 .- f)
    return q_liq, q_ice
end
