"""
    condensate_liquid_fraction(T) -> Real

Linear liquid fraction used in Swirl-LM CloudBench post-processing:

``f_l = \\mathrm{clamp}((T - 233\\,\\mathrm{K})/(273.15\\,\\mathrm{K} - 233\\,\\mathrm{K}), 0, 1)``.

At `T \\leq 233\\,\\mathrm{K}` all condensate is treated as ice; at `T \\geq 273.15\\,\\mathrm{K}` as liquid.
Documented with the [CloudBench dataset](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md).
"""
@inline function condensate_liquid_fraction(T::FT)::FT where {FT <: Real}
    t_icenuc = FT(233.0)
    t_freeze = FT(273.15)
    f_l = (T - t_icenuc) / (t_freeze - t_icenuc)
    return clamp(f_l, zero(FT), one(FT))
end

"""
    split_q_c(q_c, T) -> (q_liq, q_ice)

Given condensed-phase specific humidity `q_c` (kg/kg) from CloudBench `data.zarr` and air temperature `T` (K),
return `(q_liq, q_ice)` by apportioning `q_c` with [`condensate_liquid_fraction`](@ref).

The published variable table lists `q_c` as condensed-phase specific humidity; it also lists separate hydrometeors
such as `q_r` and `q_s`—this function only splits **`q_c`**, not rain or snow.
"""
@inline function split_q_c(q_c::FT, T::FT)::Tuple{FT,FT} where {FT <: Real}
    f = condensate_liquid_fraction(T)
    q_l = q_c * f
    q_i = q_c * (one(FT) - f)
    return q_l, q_i
end
