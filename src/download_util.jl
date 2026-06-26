using Downloads: Downloads

"""
    _download_atomic(url, dest; retries=2) -> dest

Download `url` to `dest` **atomically**: fetch into a temporary file in the same directory, then `mv` it into
place. This guarantees `dest` never contains a partially-written file — an interrupted or failed download leaves
no file at `dest`, so a later `isfile(dest)` cache check cannot be fooled by a truncated download.

Retries up to `retries` additional times on failure (so `retries + 1` total attempts). Throws if every attempt
fails. The parent directory of `dest` is created if needed.

Used by [`download_cloudbench_raw!`](@ref) and [`ensure_cloudbench_sounding_local!`](@ref); callers handle their own
`isfile(dest)` skip-if-present and `cloudbench_info` logging before calling this.
"""
function _download_atomic(url::AbstractString, dest::AbstractString; retries::Int = 2)
    dir = dirname(dest)
    mkpath(dir)
    last_err = nothing
    for _ in 0:retries
        tmp = tempname(dir; cleanup = false)
        try
            Downloads.download(String(url), tmp)
            mv(tmp, dest; force = true)
            return dest
        catch err
            last_err = err
            isfile(tmp) && rm(tmp; force = true)
        end
    end
    error("failed to download $(url) → $(dest) after $(retries + 1) attempt(s); last error: $(last_err)")
end
