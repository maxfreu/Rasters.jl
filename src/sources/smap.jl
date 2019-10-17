# A data source for SMAP (Soil moisture active-passive) datatsets.

using HDF5, Dates

export SMAPstack, SMAPseries

const SMAPMISSING = -9999.0
const SMAPEXTENT = "Metadata/Extent"
const SMAPGEODATA = "Geophysical_Data"


# Stack ########################################################################

@GeoStackMixin struct SMAPstack{} <: AbstractGeoStack{T} end

dims(stack::SMAPstack) = stack.dims
refdims(stack::SMAPstack) = (safeapply(smaptime, stack, source(stack)),)
metadata(stack::SMAPstack, args...) = nothing
missingval(stack::SMAPstack, args...) = SMAPMISSING

@inline safeapply(f, ::SMAPstack, path::AbstractString) = h5open(f, path)

data(s::SMAPstack, dataset, key::Key) =
    GeoArray(read(dataset[smappath(key)]), dims(s), refdims(s), metadata(s), missingval(s), Symbol(key))
data(s::SMAPstack, dataset, key::Key, I...) = begin
    data = dataset[smappath(key)][I...]
    GeoArray(data, slicedims(dims(s), refdims(s), I)..., metadata(s), missingval(s), Symbol(key))
end
data(::SMAPstack, dataset, key::Key, I::Vararg{Integer}) = dataset[smappath(key)][I...]

# HDF5 uses `names` instead of `keys` so we have to special-case it
Base.keys(stack::SMAPstack) = 
    safeapply(dataset -> Tuple(Symbol.(names(dataset[SMAPGEODATA]))), stack, source(stack))
Base.copy!(dataset::AbstractArray, src::SMAPstack, key) =
    safeapply(dataset -> copy!(dataset, dataset[smappath(key)][window2indices(src, key)...]), src, source(src))

# Series #######################################################################

"""
Series loader for SMAP folders (files in the time dimension).
It outputs a GeoSeries
"""
SMAPseries(path::AbstractString; kwargs...) =
    SMAPseries(joinpath.(path, filter_ext(path, ".h5")); kwargs...)
SMAPseries(filepaths::Vector{<:AbstractString}, dims=smapseriestime(filepaths);
           childtype=SMAPstack, 
           childdims=h5open(smapcoords, first(filepaths)), 
           window=(), kwargs...) =
    GeoSeries(filepaths, dims; childtype=childtype, childdims=childdims, window=window, kwargs...)


# Utils ########################################################################

smappath(key) = joinpath(GeoData.SMAPGEODATA, string(key))

smaptime(dataset) = begin
    meta = attrs(root(dataset)["time"])
    units = read(meta["units"])
    datestart = replace(replace(units, "seconds since " => ""), " " => "T")
    dt = DateTime(datestart) + Dates.Second(read(meta["actual_range"])[1])
    Time(dt)
end

smapseriestime(filepaths) = begin
    timeseries = h5open.(dataset -> smaptime(dataset), filepaths)
    timemeta = metadata(first(timeseries))
    (Time(val.(timeseries); metadata=timemeta),)
end

smapcoords(dataset) = begin
    proj = read(attrs(root(dataset)["EASE2_global_projection"]), "grid_mapping_name")
    if proj == "lambert_cylindrical_equal_area"
        # There are matrices for lookup but all rows/colums are identical.
        # For performance we just take a vector slice of each dim.
        latvec = read(root(dataset)["cell_lat"])[1, :]
        lonvec = read(root(dataset)["cell_lon"])[:, 1]
        (Lon(lonvec), Lat(latvec; order=Order(Reverse(), Reverse())))
    else
        error("projection $proj not supported")
    end
end