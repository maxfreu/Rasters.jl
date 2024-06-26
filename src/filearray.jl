
"""
    FileArray{S} <: DiskArrays.AbstractDiskArray

Filearray is a DiskArrays.jl `AbstractDiskArray`. Instead of holding
an open object, it just holds a filename string that is opened lazily
when it needs to be read.
"""
struct FileArray{S,T,N,Na,G,EC,HC} <: DiskArrays.AbstractDiskArray{T,N}
    filename::String
    size::NTuple{N,Int}
    name::Na
    group::G
    eachchunk::EC
    haschunks::HC
    write::Bool
end
function FileArray{S,T,N}(
    filename,
    size,
    name::Na,
    group::G=nothing,
    eachchunk::EC=size,
    haschunks::HC=DA.Unchunked(),
    write=false
) where {S,T,N,Na,G,EC,HC}
    FileArray{S,T,N,Na,G,EC,HC}(filename, size, name, group, eachchunk, haschunks, write)
end
function FileArray{S,T,N}(filename::String, size::Tuple;
    name=nokw, group=nokw, eachchunk=size, haschunks=DA.Unchunked(), write=false
) where {S,T,N}
    name = isnokw(name) ? nothing : name
    group = isnokw(group) ? nothing : group
    FileArray{S,T,N}(filename, size, name, group, eachchunk, haschunks, write)
end

# FileArray has S, T and N parameters not recoverable from fields
ConstructionBase.constructorof(::Type{<:FileArray{S,T,N}}) where {S,T,N} = FileArray{S,T,N}

filename(A::FileArray) = A.filename
DD.name(A::FileArray) = A.name
Base.size(A::FileArray) = A.size
DA.eachchunk(A::FileArray) = A.eachchunk
DA.haschunks(A::FileArray) = A.haschunks

# Run function `f` on the result of _open for the file type
function Base.open(f::Function, A::FileArray{S}; write=A.write, kw...) where S
    _open(f, S(), filename(A); name=name(A), write, kw...)
end

function DA.readblock!(A::FileArray, dst, r::AbstractUnitRange...)
    open(A) do O
        DA.readblock!(O, dst, r...)
    end
end
function DA.writeblock!(A::FileArray, src, r::AbstractUnitRange...)
    open(A; write=A.write) do O
        DA.writeblock!(O, src, r...)
    end
end


"""
    RasterDiskArray <: DiskArrays.AbstractDiskArray

A basic DiskArrays.jl wrapper for objects that don't have one defined yet.
When we `open` a `FileArray` it is replaced with a `RasterDiskArray`.
"""
struct RasterDiskArray{S,T,N,V,EC,HC,A} <: DiskArrays.AbstractDiskArray{T,N}
    var::V
    eachchunk::EC
    haschunks::HC
    attrib::A
end
function RasterDiskArray{S}(
    var::V, eachchunk::EC=DA.eachchunk(var), haschunks::HC=DA.haschunks(var), attrib::A=nothing
) where {S,V,EC,HC,A}
    T = eltype(var)
    N = ndims(var)
    RasterDiskArray{S,T,N,V,EC,HC,A}(var, eachchunk, haschunks, attrib)
end

Base.parent(A::RasterDiskArray) = A.var
Base.size(A::RasterDiskArray{<:Any,T,N}) where {T,N} = size(parent(A))::NTuple{N,Int}

DA.haschunks(A::RasterDiskArray) = A.haschunks
DA.eachchunk(A::RasterDiskArray) = A.eachchunk
DA.readblock!(A::RasterDiskArray, aout, r::AbstractUnitRange...) = aout .= parent(A)[r...]
DA.writeblock!(A::RasterDiskArray, v, r::AbstractUnitRange...) = parent(A)[r...] .= v

# Already open, doesn't use `name`
_open(f, ::Source, A::RasterDiskArray; name=nokw, group=nokw) = f(A)

struct MissingDiskArray{T,N,V} <: DiskArrays.AbstractDiskArray{T,N}
    var::V
end
function MissingDiskArray(::Type{MT}, var::A) where {MT,A <: AbstractArray{T,N}} where {T,N}
    MissingDiskArray{MT,N,A}(var)
end
MissingDiskArray{MT,N}(var::V) where {MT,N,V} = MissingDiskArray{MT,N,V}(var)

struct MissingDiskArrayConstructor{T,N} end
(::MissingDiskArrayConstructor{T,N})(var) where {T,N} = MissingDiskArray{T,N}(var)

ConstructionBase.constructorof(::Type{MissingDiskArray{T,N,V}}) where {T,N,V} =
    MissingDiskArrayConstructor{T,N}()

Base.parent(A::MissingDiskArray) = A.var
Base.size(A::MissingDiskArray) = size(parent(A))

DA.haschunks(A::MissingDiskArray) = DA.haschunks(parent(A))
DA.eachchunk(A::MissingDiskArray) = DA.eachchunk(parent(A))
DA.readblock!(A::MissingDiskArray, aout, r::AbstractUnitRange...) = DA.readblock!(parent(A), aout, r...)
DA.writeblock!(A::MissingDiskArray, v, r::AbstractUnitRange...) = DA.writeblock!(parent(A), v, r...)
