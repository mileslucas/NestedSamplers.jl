
struct MultiEllipsoid{T,E <: Ellipsoid{T}} <: AbstractBoundingSpace{T}
    ellipsoids::Vector{E}
end
MultiEllipsoid(ndims::Integer) = MultiEllipsoid(Float64, ndims)
MultiEllipsoid(T::Type, ndims::Integer) = MultiEllipsoid([Ellipsoid(T, ndims)])

Base.broadcastable(me::MultiEllipsoid) = (me,)
Base.length(me::MultiEllipsoid) = length(me.ellipsoids)
Base.ndims(me::MultiEllipsoid) = ndims(me.ellipsoids[1])

volume(me::MultiEllipsoid) = sum(volume, me.ellipsoids)

function scale!(me::MultiEllipsoid, factor)
    scale!.(me.ellipsoids, factor)
    return me
end

function fit(::Type{<:MultiEllipsoid}, x::AbstractMatrix; pointvol = 0)
    parent = fit(Ellipsoid, x, pointvol = pointvol)
    ells = fit(MultiEllipsoid, x, parent, pointvol = pointvol)
    return MultiEllipsoid(ells)
end

function fit(::Type{<:MultiEllipsoid}, x::AbstractMatrix, parent::Ellipsoid; pointvol = 0)
    ndim, npoints = size(x)

    # Clustering will fail with fewer than k=2 points
    npoints ≤ 2 && return [parent]

    p1, p2 = endpoints(parent)
    starting_points = hcat(p1, p2)
    R = kmeans!(x, starting_points; maxiter = 10)
    labels = assignments(R)
    x1, x2 = [x[:, l .== labels] for l in unique(labels)] 

    # if either cluster has fewer than ndim points, it is ill-defined
    if size(x1, 2) < 2ndim || size(x2, 2) < 2ndim
        return [parent]
    end

    # Getting bounding ellipsoid for each cluster
    ell1, ell2 = fit.(Ellipsoid, (x1, x2), pointvol = pointvol)

    # If total volume decreased by over half, recurse
    if volume(ell1) + volume(ell2) < 0.5volume(parent)
        return vcat(fit(MultiEllipsoid, x1, ell1, pointvol = pointvol), 
                    fit(MultiEllipsoid, x2, ell2, pointvol = pointvol))
    end

    # Otherwise see if total volume is much larger than expected 
    # and split into more than 2 clusters
    if volume(parent) > 2npoints * pointvol
        out = vcat(fit(MultiEllipsoid, x1, ell1, pointvol = pointvol), 
                    fit(MultiEllipsoid, x2, ell2, pointvol = pointvol))
        sum(volume, out) < 0.5volume(parent) && return out
    end

    # Otherwise, return single bounding ellipse
    return [parent]
end

Base.in(x::AbstractVector, me::MultiEllipsoid) = any(e->x ∈ e, me.ellipsoids)

function Base.rand(rng::AbstractRNG, me::MultiEllipsoid)   
    length(me) == 1 && return rand(rng, me.ellipsoids[1])

    # Select random ellipsoid
    vols = volume.(me.ellipsoids)
    idx = rand(rng, Categorical(vols ./ sum(vols)))
    ell = me.ellipsoids[idx]

    # Select point
    x = rand(rng, ell)

    # How many ellipsoids is the sample in
    n = count(e->x ∈ e, me.ellipsoids)

    # Only accept with probability 1/n
    return n == 1 || rand(rng) < 1 / n ? x : rand(rng, me)
end