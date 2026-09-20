"""
Swirl-LM's physical constants, verbatim from
[`swirl_lm/physics/constants.py`](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/physics/constants.py).
"""
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
Parameters of Swirl-LM's water thermodynamics, the defaults of the `Water` message in
[`swirl_lm/physics/thermodynamics/thermodynamics.proto`](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/physics/thermodynamics/thermodynamics.proto#L85-L221),
which is what [`DefaultThermodynamicsBackend`](@ref) implements.

These are **defaults**. Each CloudBench case was launched from a `config.pbtxt` that could have overridden any
of them, and that file is not published — `parameters.json` gives `config_path` as a Google-internal `/cns/`
path which is not mirrored beside the case's other files. See `docs/cloudbench_reference.md` §10.

The set is self-consistent, which is evidence it was used as a set rather than partly overridden:
`e_int_v0 == lh_v0 - r_v * t_0` and `e_int_i0 == lh_s0 - lh_v0` both hold to the digits given.

`cp_d` is not a field of the message: Swirl-LM derives it as `cv_d + R_D`
([`water.py:135-140`](https://github.com/google-research/swirl-lm/blob/main/swirl_lm/physics/thermodynamics/water.py#L135-L140)).
It is 1003.59 J/kg/K, which is **not** `SWIRL_LM_CONSTANTS.CP` (1003.415 J/kg/K); Swirl-LM uses both, the
former in `cp_m` and the latter in the fast solver's first guess.
"""
const SWIRL_LM_WATER = (;
    # The gas constant of water vapor, in units of J/kg/K.
    r_v = 461.89,

    # The reference temperature the latent heats are anchored at, in units of K.
    t_0 = 273.0,

    # The minimum temperature allowed, in units of K.
    t_min = 250.0,

    # The temperature at freezing condition, in units of K.
    t_freeze = 273.15,

    # The triple point temperature, in units of K.
    t_triple = 273.16,

    # The homogeneous ice nucleation temperature, in units of K.
    t_icenuc = 233.0,

    # The triple point pressure, in units of Pa.
    p_triple = 611.7,

    # The reference pressure used in the definition of potential temperature, in units of Pa.
    p00 = 1.0e5,

    # The reference specific internal energy of water vapor, in units of J/kg.
    e_int_v0 = 2.132e6,

    # The reference specific internal energy of ice, in units of J/kg.
    e_int_i0 = 3.34e5,

    # The latent heat of vaporization at `t_0`, in units of J/kg.
    lh_v0 = 2.258e6,

    # The latent heat of sublimation at `t_0`, in units of J/kg.
    lh_s0 = 2.592e6,

    # Specific heat of dry air at constant volume, J/kg/K.
    cv_d = 716.9,

    # Specific heat of water vapor at constant volume, J/kg/K.
    cv_v = 1397.11,

    # Specific heat of liquid water at constant volume, J/kg/K.
    cv_l = 4217.4,

    # Specific heat of ice at constant volume, J/kg/K.
    cv_i = 2050.0,

    # Specific heat of dry air at constant pressure, J/kg/K; derived, not a field of the message.
    cp_d = 716.9 + 286.69,

    # Specific heat of water vapor at constant pressure, J/kg/K.
    cp_v = 1859.0,

    # Specific heat of liquid water at constant pressure, J/kg/K.
    cp_l = 4219.9,

    # Specific heat of ice at constant pressure, J/kg/K.
    cp_i = 2050.0,

    # The maximum number of iterations of the temperature solver.
    max_temperature_iterations = 101,

    # The atol and rtol of the temperature solver.
    temperature_tolerance = 1.0e-2,

    # The number of iterations for density computation.
    num_density_iterations = 1,
)
