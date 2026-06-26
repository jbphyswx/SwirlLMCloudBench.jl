using ..Catalog: Catalog

"""
    CloudBenchSelection(site_ids, months, experiments)

Lazy description of a subset of the `(site_id, month, experiment)` index space. Constructing this does **not** perform
remote I/O. Iterate the selection or use [`each_simulation`](@ref) to obtain lightweight [`CloudBenchSimulation`](@ref)
values (remote Zarr output, no loaded metadata) without materializing an array of all triples.

Axes must be iterable; `experiments` entries are `Symbol`s (catalog experiments).
"""
struct CloudBenchSelection{S,M,E}
    site_ids::S
    months::M
    experiments::E
end

"""All published sites, seasonal months, and catalog experiments (no network)."""
function CloudBenchSelection()
    CloudBenchSelection(Catalog.CLOUDBENCH_CASE_INDICES, Catalog.CLOUDBENCH_MONTHS, Catalog.EXPERIMENTS)
end

"""
    each_simulation(sel::CloudBenchSelection)

Iterator over [`CloudBenchSimulation`](@ref) for each triple in the Cartesian product of the three axes.
Does not allocate an array of all simulations.
"""
function each_simulation(sel::CloudBenchSelection)
    (
        CloudBenchSimulation(Int(si), Int(mo), ex)
        for ex in sel.experiments
        for mo in sel.months
        for si in sel.site_ids
    )
end

function Base.length(sel::CloudBenchSelection)
    return length(sel.site_ids) * length(sel.months) * length(sel.experiments)
end

Base.eltype(::Type{CloudBenchSelection{S,M,E}}) where {S,M,E} = CloudBenchSimulationRemote
Base.IteratorSize(::Type{<:CloudBenchSelection}) = Base.HasLength()

# Single source of truth for ordering: delegate iteration to `each_simulation` rather than re-implementing the
# Cartesian product, so the two can never drift out of sync.
Base.iterate(sel::CloudBenchSelection, state...) = iterate(each_simulation(sel), state...)
