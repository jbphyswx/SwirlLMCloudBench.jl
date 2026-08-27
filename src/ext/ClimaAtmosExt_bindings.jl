# --- Optional weak-dep API (methods added when extensions load; MethodError if called without the extra package) ---
# ClimaAtmos extension (SwirlLMCloudBenchClimaAtmosExt): single-column forcing from a CloudBench sounding,
# reusing ClimaAtmos's GCM-driven (Shen et al. 2022) cache + tendency.
function climaatmos_pkg_version end
function ClimaAtmosSwirlLMCloudBenchForcing end                       # in-memory CloudBenchForcing (GCM-driven forcing object)
function ClimaAtmosSwirlLMCloudBenchSetup end                          # ClimaAtmosSwirlLMCloudBenchSetup (ICs + forcing) for ClimaAtmos.AtmosSimulation
function write_ClimaAtmosSwirlLMCloudBenchForcing_netcdf! end          # serialize a CloudBenchForcing
function read_ClimaAtmosSwirlLMCloudBenchForcing end                   # and read it back
function ClimaAtmos_SwirlLMCloudBench_toml_overrides end                 # ClimaParams overrides putting a column on CloudBench's configuration
function ClimaAtmos_SwirlLMCloudBench_params end                         # ClimaAtmosParameters built with those overrides
function ClimaAtmos_SwirlLMCloudBench_callback_kwargs end                # callback_kwargs refreshing RRTMGP on CloudBench's cadence
