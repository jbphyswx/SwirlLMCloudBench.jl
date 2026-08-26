using CSV: CSV

"""
Symbols for every column in published CloudBench `sounding.csv` files (see the
[CloudBench README](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/README.md)).
`sounding.csv` must include **all** of these headers for [`CloudBenchSounding`](@ref) to parse.

The CSV column named `T` is distinct from `temperature`; it is stored as field `T_column` (`s.T` aliases it).
"""
const CLOUDBENCH_SOUNDING_COLUMNS = (
    :z,
    :theta_li,
    :temperature,
    :q_t,
    :u,
    :v,
    :w,
    :T_adv_src,
    :q_t_adv_src,
    :T,
    :p,
    :rho,
    :cld_frac,
)

"""Comma-separated header line matching [`CLOUDBENCH_SOUNDING_COLUMNS`](@ref)."""
const CLOUDBENCH_SOUNDING_CSV_HEADER =
    "z,theta_li,temperature,q_t,u,v,w,T_adv_src,q_t_adv_src,T,p,rho,cld_frac"

"""
`units` and `long_name` of each sounding column.

`T` is the GCM temperature: `gcm_column.py` maps it to `gcm_T`, the profile the forcing advects and relaxes toward,
while `temperature` initializes the reference state. The two are equal in the published soundings.
"""
const CLOUDBENCH_SOUNDING_ATTRIBUTES = (;
    z = ("m", "Height above the surface"),
    theta_li = ("K", "Liquid-ice potential temperature"),
    temperature = ("K", "Air temperature used to initialize the reference state"),
    q_t = ("kg kg^-1", "Total water specific humidity"),
    u = ("m s^-1", "Zonal velocity"),
    v = ("m s^-1", "Meridional velocity"),
    w = ("m s^-1", "Vertical velocity"),
    T_adv_src = ("K s^-1", "GCM total advective tendency of temperature"),
    q_t_adv_src = ("kg kg^-1 s^-1", "GCM total advective tendency of total water specific humidity"),
    T = ("K", "GCM air temperature"),
    p = ("Pa", "Pressure"),
    rho = ("kg m^-3", "Air density"),
    cld_frac = ("1", "Cloud fraction"),
)

"""Swirl-LM's physical constants, verbatim from `swirl_lm/physics/constants.py`."""
const SWIRL_LM_CONSTANTS = (;
    # Universal gas constant, in units of J/mol/K.
    R_UNIVERSAL = 8.3145,

    # The precomputed gas constant for dry air, in units of J/kg/K.
    R_D = 286.69,

    # The gravitational acceleration constant, in units of N/kg.
    G = 9.81,

    # The heat capacity ratio of dry air, dimensionless.
    GAMMA = 1.4,

    # The constant pressure heat capacity of dry air, in units of J/kg/K.
    CP = 1.4 * 286.69 / (1.4 - 1.0),

    # The constant volume heat capacity of dry air, in units of J/kg/K.
    CV = (1.4 * 286.69 / (1.4 - 1.0)) - 286.69,

    # The molecular mass of dry air (kg/mol).
    DRY_AIR_MOL_MASS = 0.0289647,

    # The molecular mass of water (kg/mol).
    WATER_MOL_MASS = 0.0180153,

    # Avogadro's number.
    AVOGADRO = 6.022e23,
)

"""
    CloudBenchSounding{FT<:AbstractFloat,V<:AbstractVector{FT}}

Parsed snapshot of a CloudBench **`sounding.csv`** row table (one height per row). Published bucket files such as
[`cloudbench-simulation-output`](https://storage.googleapis.com/cloudbench-simulation-output/index.html) use the schema in
[`CLOUDBENCH_SOUNDING_COLUMNS`](@ref); [`CloudBenchSounding(path)`](@ref) requires **every** column.

For programmatic tests or synthetic columns, construct [`CloudBenchSounding`](@ref) with thirteen matching-length vectors.

    CloudBenchSounding(path; eltype=Float32)
    CloudBenchSounding{FT,V}(z, theta_li, temperature, q_t, u, v, w, T_adv_src, q_t_adv_src, T_column, p, rho, cld_frac)

# Fields

Field `T_column` holds the CSV column whose header is `T` (use `s.T` in Julia; it is not the type parameter `FT`).

# Type parameters

`FT` is the element type; all profile columns share the same vector type `V` (e.g. `Vector{Float32}`).
"""
struct CloudBenchSounding{FT<:AbstractFloat,V<:AbstractVector{FT}}
    z::V
    theta_li::V
    temperature::V
    q_t::V
    u::V
    v::V
    w::V
    T_adv_src::V
    q_t_adv_src::V
    T_column::V
    p::V
    rho::V
    cld_frac::V
    function CloudBenchSounding{FT,V}(
        z::V,
        theta_li::V,
        temperature::V,
        q_t::V,
        u::V,
        v::V,
        w::V,
        T_adv_src::V,
        q_t_adv_src::V,
        T_column::V,
        p::V,
        rho::V,
        cld_frac::V,
    ) where {FT<:AbstractFloat,V<:AbstractVector{FT}}
        n = length(z)
        for (name, col) in (
            ("z", z),
            ("theta_li", theta_li),
            ("temperature", temperature),
            ("q_t", q_t),
            ("u", u),
            ("v", v),
            ("w", w),
            ("T_adv_src", T_adv_src),
            ("q_t_adv_src", q_t_adv_src),
            ("T", T_column),
            ("p", p),
            ("rho", rho),
            ("cld_frac", cld_frac),
        )
            length(col) == n ||
                throw(DimensionMismatch("column $(name) length $(length(col)) must match z length $(n)"))
        end
        return new{FT,V}(
            z,
            theta_li,
            temperature,
            q_t,
            u,
            v,
            w,
            T_adv_src,
            q_t_adv_src,
            T_column,
            p,
            rho,
            cld_frac,
        )
    end
end

function Base.getproperty(s::CloudBenchSounding, name::Symbol)
    if name === :T
        return getfield(s, :T_column)
    end
    return getfield(s, name)
end

function Base.propertynames(s::CloudBenchSounding, private::Bool = false)
    private && return fieldnames(CloudBenchSounding)
    return (fieldnames(CloudBenchSounding)..., :T)
end

"""
    CloudBenchSounding(path; eltype=Float32) -> CloudBenchSounding{eltype,Vector{eltype}}

Parse `sounding.csv` at `path`. Requires every column in [`CLOUDBENCH_SOUNDING_COLUMNS`](@ref).
Keyword `eltype` sets the storage scalar type (default `Float32`).
"""
function CloudBenchSounding(path::AbstractString; eltype::Type{<:AbstractFloat} = Float32)
    return _read_cloudbench_sounding_from_path(path, eltype)
end

function _read_cloudbench_sounding_from_path(
    path::AbstractString,
    eltype::Type{<:AbstractFloat},
)
    F = eltype
    f = CSV.File(path; stringtype = String)
    n = length(f)
    n < 2 && error("sounding must have at least 2 levels (rows); got $n")
    names = propertynames(f)
    for c in CLOUDBENCH_SOUNDING_COLUMNS
        c in names || error(
            "sounding.csv must include column $(repr(c)); got columns $(collect(names)). " *
            "Published CloudBench soundings include every column in CLOUDBENCH_SOUNDING_COLUMNS.",
        )
    end
    z = _sounding_column_to_vector(f, :z, F, n)
    theta_li = _sounding_column_to_vector(f, :theta_li, F, n)
    temperature = _sounding_column_to_vector(f, :temperature, F, n)
    q_t = _sounding_column_to_vector(f, :q_t, F, n)
    u = _sounding_column_to_vector(f, :u, F, n)
    v = _sounding_column_to_vector(f, :v, F, n)
    w = _sounding_column_to_vector(f, :w, F, n)
    T_adv_src = _sounding_column_to_vector(f, :T_adv_src, F, n)
    q_t_adv_src = _sounding_column_to_vector(f, :q_t_adv_src, F, n)
    T_column = _sounding_column_to_vector(f, :T, F, n)
    p = _sounding_column_to_vector(f, :p, F, n)
    rho = _sounding_column_to_vector(f, :rho, F, n)
    cld_frac = _sounding_column_to_vector(f, :cld_frac, F, n)
    return CloudBenchSounding{eltype,Vector{eltype}}(
        z,
        theta_li,
        temperature,
        q_t,
        u,
        v,
        w,
        T_adv_src,
        q_t_adv_src,
        T_column,
        p,
        rho,
        cld_frac,
    )
end

"""
    read_cloudbench_sounding_columns(path, eltype::Type{<:AbstractFloat}=Float32)

Read a `sounding.csv` and return a `NamedTuple` of the same column names as [`CloudBenchSounding`](@ref) (keys
`T_column` for the CSV `T` column). Fails if the file is not a full public-bucket schema; use
[`CLOUDBENCH_SOUNDING_CSV_HEADER`](@ref) to build test files.
"""
function read_cloudbench_sounding_columns(path::AbstractString, eltype::Type{<:AbstractFloat} = Float32)
    s = _read_cloudbench_sounding_from_path(path, eltype)
    return (;
        z = s.z,
        theta_li = s.theta_li,
        temperature = s.temperature,
        q_t = s.q_t,
        u = s.u,
        v = s.v,
        w = s.w,
        T_adv_src = s.T_adv_src,
        q_t_adv_src = s.q_t_adv_src,
        T_column = s.T_column,
        p = s.p,
        rho = s.rho,
        cld_frac = s.cld_frac,
    )
end

function _sounding_val(x, F::Type{<:AbstractFloat})
    F(x isa AbstractString ? parse(Float64, x) : x)
end

function _sounding_column_to_vector(f::CSV.File, sym::Symbol, F::Type{<:AbstractFloat}, n::Int)
    c = getproperty(f, sym)
    length(c) == n || error("column $sym: length $(length(c)) != $n")
    return map(x -> _sounding_val(x, F), c)
end

"""
    cloudbench_sounding_zt_matrices(sounding::CloudBenchSounding, nt::Int)

Construct ``(z, \\mathrm{time})`` matrices of size `(nz, nt)` from **one** [`CloudBenchSounding`](@ref): each vertical profile
column is replicated across `nt` times (every column shares the same shape; callers decide how physical time maps to indices).

Returned names match **`sounding.csv`** column headers wherever the quantity is read directly (`temperature`, `q_t`, …).
Derived quantities use explicit names listed under **Returned keys** below.

This routine lives with other sounding helpers **without optional packages**.

## Profiles replicated on `(z, \\mathrm{time})`

Same symbols as in [`CLOUDBENCH_SOUNDING_COLUMNS`](@ref): `temperature`, `q_t`, `u`, `v`, `w`, `rho`.

## Large-scale advection split (matches Swirl [`gcm_forcing.py`](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/example/geo_flows/cloud_feedback/gcm_forcing.py))

Swirl’s [`_gcm_vertical_advection`](https://github.com/google-research/swirl-lm/blob/51289d7caf048a14aae649252ed974416277baa2/swirl_lm/example/geo_flows/cloud_feedback/gcm_forcing.py#L74-L101)
returns large-scale **vertical** advection (subsidence ``\\times`` upwind vertical derivative). It is **added** to the total large-scale advective
source in [`_q_t_horizontal_advective_tendency`](https://github.com/google-research/swirl-lm/blob/51289d7caf048a14aae649252ed974416277baa2/swirl_lm/example/geo_flows/cloud_feedback/gcm_forcing.py#L103-L131)
to form the residual Swirl labels horizontal (`total_adv + vadv`).

On the **one-dimensional** column we store three levels of detail:

1. **`temperature_vertical_advection`** / **`q_t_vertical_advection`** — column analogue of `_gcm_vertical_advection` only: [`_column_upwind_w_dphi_dz`](@ref) applied to `temperature` / `q_t` with `sounding.w` (same mathematical object as Swirl’s `w * ∂φ/∂z` upwind term on the strip).
2. **`temperature_horizontal_advective_tendency`** / **`q_t_horizontal_advective_tendency`** — `T_adv_src` + `temperature_vertical_advection` and `q_t_adv_src` + `q_t_vertical_advection` (Swirl’s combined residual per tracer).

So vertical subsidence advection **is** returned explicitly in keys (1); keys (2) repeat Swirl’s **sum** used downstream. The θ_li pathway in `_theta_li_horizontal_advective_tendency` adds pressure-work/exner handling we **do not** emulate here—the temperature-column analogue uses **`temperature`** only.

## Diagnostic derived from `w` and `rho`

**`vertical_pressure_velocity`** is ``-\\rho\\, g\\, w`` (Pa s⁻¹).

## Returned keys

`NamedTuple` of `Matrix{T}`:

`temperature`, `q_t`, `u`, `v`, `w`, `rho`,
`temperature_vertical_advection`, `q_t_vertical_advection`,
`temperature_horizontal_advective_tendency`, `q_t_horizontal_advective_tendency`, `vertical_pressure_velocity`.
"""
function cloudbench_sounding_zt_matrices(sounding::CloudBenchSounding, nt::Int)
    nt >= 1 || error("nt must be >= 1")
    T = eltype(sounding.z)
    z = sounding.z
    nz = length(z)
    nz < 2 && error("sounding must have at least 2 levels")
    # replicated (z, time) matrices — local names follow `sounding.csv` / `CLOUDBENCH_SOUNDING_COLUMNS`, not NetCDF short names
    temperature_zt = _profile_replicated(sounding.T, nz, nt)
    q_t_zt = _profile_replicated(sounding.q_t, nz, nt)
    u_zt = _profile_replicated(sounding.u, nz, nt)
    v_zt = _profile_replicated(sounding.v, nz, nt)
    rho_zt = _profile_replicated(sounding.rho, nz, nt)
    w_zt = _profile_replicated(sounding.w, nz, nt)
    # alias the stored profiles directly (read-only here; the upwind/broadcast ops below work on any AbstractVector)
    # the GCM temperature: `gcm_column.py` maps the `T` column to `gcm_T`, which is what the forcing advects
    Tvec = sounding.T
    qvec = sounding.q_t
    wvec = sounding.w
    tadv = sounding.T_adv_src
    qadv = sounding.q_t_adv_src
    vadv_T = _column_upwind_w_dphi_dz(wvec, Tvec, z)
    vadv_q = _column_upwind_w_dphi_dz(wvec, qvec, z)
    # Remove an estimate of the vertical component from the total advective
    # tendency. The residual will be an estimate of the horizontal advective
    # tendency. Note that the GCM advective tendency corresponds to the negative
    # of the GCM advection term, so to remove the vertical contribution the
    # vertical advection term needs to be added; not subtracted. 
    # see  https://github.com/google-research/swirl-lm/blob/51289d7caf048a14aae649252ed974416277baa2/swirl_lm/example/geo_flows/cloud_feedback/gcm_forcing.py#L122-L126
    T_hadv_profile = tadv .+ vadv_T
    q_t_hadv_profile = qadv .+ vadv_q
    temperature_vertical_advection_zt = _profile_replicated(vadv_T, nz, nt)
    q_t_vertical_advection_zt = _profile_replicated(vadv_q, nz, nt)
    temperature_hadv_zt = _profile_replicated(T_hadv_profile, nz, nt)
    q_t_hadv_zt = _profile_replicated(q_t_hadv_profile, nz, nt)
    vertical_pressure_velocity_profile = @. -sounding.rho * T(SWIRL_LM_CONSTANTS.G) * wvec
    vertical_pressure_velocity_zt = _profile_replicated(vertical_pressure_velocity_profile, nz, nt)
    return (;
        temperature = temperature_zt,
        q_t = q_t_zt,
        u = u_zt,
        v = v_zt,
        w = w_zt,
        rho = rho_zt,
        temperature_vertical_advection = temperature_vertical_advection_zt,
        q_t_vertical_advection = q_t_vertical_advection_zt,
        temperature_horizontal_advective_tendency = temperature_hadv_zt,
        q_t_horizontal_advective_tendency = q_t_hadv_zt,
        vertical_pressure_velocity = vertical_pressure_velocity_zt,
    )
end

"""
    _column_upwind_w_dphi_dz(w, phi, z) -> Vector

1D first-order upwind estimate of `w * ∂φ/∂z` on a monotonic height column `z` (length ≥ 2), matching the
vertical advection **stencil** used in Swirl-LM’s GCM driver (upwind in the sign of `w`) for a single column.
"""
function _column_upwind_w_dphi_dz(
    w::AbstractVector{T},
    phi::AbstractVector{T},
    z::AbstractVector{T},
) where {T<:AbstractFloat}
    n = length(z)
    n == length(phi) == length(w) || error("w, phi, z must have the same length")
    n >= 2 || error("column upwind needs at least 2 levels")
    out = Vector{T}(undef, n)
    for k in 1:n
        dphidz = if w[k] >= 0
            if k == 1
                (phi[2] - phi[1]) / (z[2] - z[1])
            else
                (phi[k] - phi[k - 1]) / (z[k] - z[k - 1])
            end
        else
            if k == n
                (phi[n] - phi[n - 1]) / (z[n] - z[n - 1])
            else
                (phi[k + 1] - phi[k]) / (z[k + 1] - z[k])
            end
        end
        out[k] = w[k] * dphidz
    end
    return out
end

function _profile_replicated(profile::AbstractVector{T}, nz, nt) where {T}
    mat = Matrix{T}(undef, nz, nt)
    for j in 1:nt
        mat[:, j] .= profile
    end
    return mat
end

# Value semantics: the struct holds mutable `Vector`s, so the `===`-based fallbacks compare/hash by identity.
# Define `==`/`hash` by content so two independently-parsed-but-equal soundings compare equal (and `CloudBenchMetadata`
# equality, which delegates here, works for loaded simulations).
function Base.:(==)(a::CloudBenchSounding, b::CloudBenchSounding)
    for f in fieldnames(CloudBenchSounding)
        getfield(a, f) == getfield(b, f) || return false
    end
    return true
end

function Base.hash(s::CloudBenchSounding, h::UInt)
    h = hash(:CloudBenchSounding, h)
    for f in fieldnames(CloudBenchSounding)
        h = hash(getfield(s, f), h)
    end
    return h
end

function Base.show(io::IO, s::CloudBenchSounding)
    n = length(s.z)
    print(io, "CloudBenchSounding(", n, " vertical level", n == 1 ? "" : "s", ")")
end
