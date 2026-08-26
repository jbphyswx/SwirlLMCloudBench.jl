# --- Optional weak-dep API (methods added when extensions load; MethodError if called without the extra package) ---
# ClimaAtmos extension (SwirlLMCloudBenchClimaAtmosExt): single-column forcing from a CloudBench sounding,
# reusing ClimaAtmos's GCM-driven (Shen et al. 2022) cache + tendency.
function climaatmos_pkg_version end
function cloudbench_forcing end                       # in-memory CloudBenchForcing (GCM-driven forcing object)
function cloudbench_setup end                          # CloudBenchSetup (ICs + forcing) for ClimaAtmos.AtmosSimulation
function write_cloudbench_forcing_netcdf! end          # serialize a CloudBenchForcing
function read_cloudbench_forcing end                   # and read it back
# OhMyThreads / Distributed extensions:
function cloudbench_tmap end
function cloudbench_pmap_download_raw! end
