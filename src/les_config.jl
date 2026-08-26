"""
The configuration the published CloudBench LES were run with.

Values are from Chammas et al. (2026) and the upstream `cloud_feedback` sources; each entry names its source. The
`GCMSettings` dataclass defaults in `gcm_settings.py` are **not** these — the run values come from the paper and the
per-case `config.pbtxt`.
"""

"""Domain, grid and timestep of every CloudBench LES (Chammas et al. 2026, "Domain size and resolution")."""
const CLOUDBENCH_LES_GRID = (;
    lx = 6000.0,        # m
    ly = 6000.0,        # m
    lz = 6000.0,        # m
    nx = 128,
    ny = 128,
    nz = 480,
    dx = 48.8,          # m
    dy = 48.8,          # m
    dz = 12.5,          # m
    dt = 0.2,           # s
    duration_days = 5,
)

"""
Relaxation toward the driving GCM (Chammas et al. 2026, "Nudging and sponge layer"; form in
`gcm_forcing.py:_inverse_relaxation_time_scale_fn`).

`q_t` and `θ_li` are relaxed only above `z_i`, ramping to `1/tau_tropo` over `z_i → z_r` as a raised cosine. Horizontal
momentum is relaxed over the whole column at `1/tau_wind`, with no height dependence.
"""
const CLOUDBENCH_RELAXATION = (;
    z_i = 4000.0,       # m
    z_r = 6000.0,       # m, z_i plus the 2 km ramp
    tau_tropo = 21600.0,  # s
    tau_wind = 21600.0,   # s
)

"""Rayleigh sponge on vertical velocity in the top 1 km of the domain (Chammas et al. 2026)."""
const CLOUDBENCH_SPONGE_DEPTH = 1000.0

"""
Microphysics of the CloudBench LES (Chammas et al. 2026, "Microphysics").

Single-moment warm rain, Kessler-based, coefficients calibrated by EKI against superdroplet simulations. Cloud droplets
are monodisperse at a fixed number concentration; condensation is instantaneous (thermodynamic equilibrium) rather than
relaxed; terminal velocity is a linear combination of gamma-type functions rather than a power law.
"""
const CLOUDBENCH_MICROPHYSICS = (;
    n_droplets = 1.0e8,   # m^-3
    t_ice_nucleation = CONDENSATE_T_ICENUC,
    t_freeze = CONDENSATE_T_FREEZE,
)

"""
Radiation of the CloudBench LES (Chammas et al. 2026, "Radiative transfer").

RRTMGP two-stream. The column is extended above the 6 km domain to the GCM top for the radiative calculation, and that
extension is held cloud-free.
"""
const CLOUDBENCH_RADIATION = (;
    update_interval = 240.0,   # s
    co2_ppm_baseline = 400.0,
    asymmetry_factor = 0.8,
)

"""
    cloudbench_co2_vmr(experiment) -> Float64

CO₂ volume mixing ratio [mol/mol] of a CloudBench experiment.

The scenarios are SST and CO₂ perturbations of the baseline, which is well mixed at 400 ppm: `amip` and `amip_p4k`
keep that, `amip_p4k_2xco2` doubles it, and `amip_4xco2` and `amip_p4k_4xco2` quadruple it (Chammas et al. 2026).
"""
function cloudbench_co2_vmr(experiment)
    e = Catalog.parse_experiment(experiment isa Catalog.CloudBenchExperiment ? Symbol(experiment) : experiment)
    baseline = CLOUDBENCH_RADIATION.co2_ppm_baseline * 1.0e-6
    e === :amip && return baseline
    e === :amip_p4k && return baseline
    e === :amip_p4k_2xco2 && return 2 * baseline
    e === :amip_4xco2 && return 4 * baseline
    e === :amip_p4k_4xco2 && return 4 * baseline
    return error("no CO₂ concentration recorded for experiment $(repr(e))")
end

"""
Condensate mass fraction above which a grid cell counts as cloudy, and a column as cloudy at any height.

Defines `cloud_fraction` and `cloud_cover` in the published output (upstream CloudBench README).
"""
const CLOUDBENCH_CLOUD_THRESHOLD = 1.0e-6

"""
Chunking of the 3-D variables in `data.zarr` (upstream CloudBench README).

Eight chunks along the vertical. Reads aligned to these avoid fetching a chunk per element.
"""
const CLOUDBENCH_ZARR_CHUNK = (; nx = 124, ny = 124, nz = 60, n_vertical_chunks = 8)

"""Interval between stored output samples in `data.zarr`, which covers the last simulated day only (upstream README)."""
const CLOUDBENCH_OUTPUT_INTERVAL = 1200.0
