"""
    MeshQuadrilateralModule

Module  for generation of meshes composed of quadrilaterals.
"""
module MeshQuadrilateralModule

__precompile__(true)

import ..FESetModule: AbstractFESet, FESetQ4, FESetQ8, FESetQ9, bfun, cat, connasarray, FESetL2
import ..FENodeSetModule: FENodeSet, count
import ..MeshModificationModule: mergemeshes, updateconn!
import ..MeshSelectionModule: connectednodes
import ..MeshUtilModule:
    makecontainer, addhyperface!, findhyperface!, linearspace, linearspace
import LinearAlgebra: norm
import Statistics: mean

"""
    Q4annulus(rin::T, rex::T, nr::IT, nc::IT, Angl::T) where {T<:Number, IT<:Integer}

Mesh of an annulus segment.

Mesh of an annulus segment, centered at the origin, with internal radius `rin`,
and  external radius `rex`, and  development angle `Angl` (in radians). Divided
into elements: nr, nc in the radial and circumferential direction respectively.
"""
function Q4annulus(rin::T, rex::T, nr::IT, nc::IT, Angl::T) where {T<:Number, IT<:Integer}
    trin = min(rin, rex)
    trex = max(rin, rex)
    fens, fes = Q4block(trex - trin, Angl, nr, nc)
    xy = fens.xyz
    for i in eachindex(fens)
        r = trin + xy[i, 1]
        a = xy[i, 2]
        xy[i, :] = [r * cos(a) r * sin(a)]
    end
    fens.xyz = xy
    return fens, fes
end

"""
    Q4quadrilateral(xyz::Matrix{T}, nL::IT, nW::IT) where {T<:Number, IT<:Integer}

Mesh of a general quadrilateral given by the location of the vertices.
"""
function Q4quadrilateral(xyz::Matrix{T}, nL::IT, nW::IT) where {T<:Number, IT<:Integer}
    npts = size(xyz, 1)
    if npts == 2 # In this case the quadrilateral must be defined in two dimensions
        lo = minimum(xyz, dims = 1)
        hi = maximum(xyz, dims = 1)
        xyz = [
            [lo[1] lo[2]]
            [hi[1] lo[2]]
            [hi[1] hi[2]]
            [lo[1] hi[2]]
        ]
    elseif npts != 4
        error("Need 2 or 4 points")
    end

    fens, fes = Q4block(2.0, 2.0, nL, nW)

    xyz1 = fens.xyz
    if (size(xyz1, 2) < size(xyz, 2))
        nxyz1 = zeros(T, size(xyz1, 1), size(xyz, 2))
        nxyz1[:, 1:size(xyz1, 2)] = xyz1
        xyz1 = nxyz1
    end

    dummy = FESetQ4(reshape(collect(1:4), 1, 4))
    pxyz = xyz1
    for i in eachindex(fens)
        N = bfun(dummy, broadcast(-, pxyz[i, :], 1.0))# shift coordinates by -1
        pxyz[i, :] = N' * xyz
    end
    fens.xyz = deepcopy(pxyz)
    return fens, fes
end

"""
    Q4elliphole(
        xradius::T,
        yradius::T,
        L::T,
        H::T,
        nL::IT,
        nH::IT,
        nW::IT,
    ) where {T<:Number, IT<:Integer}

Mesh of one quarter of a rectangular plate with an elliptical hole.

`xradius`,`yradius` = radius of the ellipse,
`L,H`= and dimensions of the plate,
`nL,nH`= numbers of edges along the side of the plate; this also happens
    to be the number of edges along the circumference of the elliptical
    hole
`nW`= number of edges along the remaining straight edge (from the hole
    in the direction of the length),
"""
function Q4elliphole(
    xradius::T,
    yradius::T,
    L::T,
    H::T,
    nL::IT,
    nH::IT,
    nW::IT,
) where {T<:Number, IT<:Integer}
    dA = pi / 2 / (nL + nH)
    tolerance = (xradius + yradius) / (nL * nH) / 100
    fens = nothing
    fes = nothing
    for i in 1:nH
        xy = [
            xradius*cos((i - 1) * dA) yradius*sin((i - 1) * dA)
            L (i-1)/nH*H
            L (i)/nH*H
            xradius*cos((i) * dA) yradius*sin((i) * dA)
        ]
        fens1, fes1 = Q4quadrilateral(xy, nW, 1)
        if (fens === nothing)
            fens = fens1
            fes = fes1
        else
            fens, fes1, fes2 = mergemeshes(fens1, fes1, fens, fes, tolerance)
            fes = cat(fes1, fes2)
        end
    end
    for i in 1:nL
        xy = [
            xradius*cos((nH + i - 1) * dA) yradius*sin((nH + i - 1) * dA)
            (nL-i+1)/nL*L H
            (nL-i)/nL*L H
            xradius*cos((nH + i) * dA) yradius*sin((nH + i) * dA)
        ]
        fens1, fes1 = Q4quadrilateral(xy, nW, 1)
        fens, fes1, fes2 = mergemeshes(fens1, fes1, fens, fes, tolerance)
        fes = cat(fes1, fes2)
    end
    return fens, fes
end

"""
    Q4block(Length::T, Width::T, nL::IT, nW::IT) where {T<:Number, IT<:Integer}

Mesh of a rectangle, Q4 elements.

Divided into elements: nL, nW in the first, second (x,y).
"""
function Q4block(Length::T, Width::T, nL::IT, nW::IT) where {T<:Number, IT<:Integer}
    return Q4blockx(
        collect(linearspace(0.0, Length, nL + 1)),
        collect(linearspace(0.0, Width, nW + 1)),
    )
end

"""
    Q4blockx(xs::Vector{T}, ys::Vector{T})

Graded mesh  of a rectangle, Q4 finite elements.

Mesh of a 2-D block, Q4 finite elements. The nodes are located at the
Cartesian product of the two intervals on the input.  This allows for
construction of graded meshes.

xs,ys - Locations of the individual planes of nodes.
"""
function Q4blockx(xs::Vector{T}, ys::Vector{T}) where {T<:Number}
    nL = length(xs) - 1
    nW = length(ys) - 1

    nnodes = (nL + 1) * (nW + 1)
    ncells = nL * nW

    # preallocate node locations
    xyz = zeros(T, nnodes, 2)
    k = 1
    for j in 1:(nW+1)
        for i in 1:(nL+1)
            xyz[k, 1] = xs[i]
            xyz[k, 2] = ys[j]
            k = k + 1
        end
    end
    # create the nodes
    fens = FENodeSet(xyz)

    #preallocate connectivity matrix
    conn = zeros(Int, ncells, 4)

    # function  nodenumbers(i,j,nL,nW)
    #     f = (j-1) * (nL+1) + i;
    #     nn = [f, (f+1), f+(nL+1)+1, f+(nL+1)];
    #     return nn
    # end

    k = 1
    for i in 1:nL
        for j in 1:nW
            f = (j - 1) * (nL + 1) + i
            conn[k, 1] = f
            conn[k, 2] = (f + 1)
            conn[k, 3] = f + (nL + 1) + 1
            conn[k, 4] = f + (nL + 1)
            k = k + 1
        end
    end
    # create the cells
    fes = FESetQ4(conn)

    return fens, fes
end

"""
    Q8block(Length::T, Width::T, nL::IT, nW::IT) where {T<:Number, IT<:Integer}

Mesh of a rectangle of Q8 elements.
"""
function Q8block(Length::T, Width::T, nL::IT, nW::IT) where {T<:Number, IT<:Integer}
    fens, fes = Q4block(Length, Width, nL, nW)
    fens, fes = Q4toQ8(fens, fes)
end

"""
    Q4toQ8(fens::FENodeSet, fes::FESetQ4)

Convert a mesh of quadrilateral Q4 to quadrilateral Q8.
"""
function Q4toQ8(fens::FENodeSet, fes::FESetQ4)
    nedges = 4
    ec = [1 2; 2 3; 3 4; 4 1]
    conns = connasarray(fes)
    # Additional node numbers are numbered from here
    newn = count(fens) + 1
    # make a search structure for edges
    edges = makecontainer()
    for i in axes(conns, 1)
        conn = conns[i, :]
        for J in 1:nedges
            ev = conn[ec[J, :]]
            newn = addhyperface!(edges, ev, newn)
        end
    end
    xyz1 = fens.xyz             # Pre-existing nodes
    # Allocate for vertex nodes plus edge nodes plus face nodes
    xyz = zeros(eltype(xyz1), newn - 1, size(xyz1, 2))
    xyz[1:size(xyz1, 1), :] = xyz1 # existing nodes are copied over
    # calculate the locations of the new nodes
    # and construct the new nodes
    for i in keys(edges)
        C = edges[i]
        for J in eachindex(C)
            ix = vec([item for item in C[J].o])
            push!(ix, i) # Add the anchor point as well
            xyz[C[J].n, :] = mean(xyz[ix, :], dims = 1)
        end
    end
    # construct new geometry cells
    nconns = zeros(Int, size(conns, 1), 8)
    nc = 1
    for i in axes(conns, 1)
        conn = conns[i, :]
        econn = zeros(Int, 1, nedges)
        for J in 1:nedges
            ev = conn[ec[J, :]]
            h, n = findhyperface!(edges, ev)
            econn[J] = n
        end
        nconns[nc, :] = vcat(vec(conn), vec(econn))
        nc = nc + 1
    end
    fens = FENodeSet(xyz)
    fes = FESetQ8(nconns)
    return fens, fes
end

"""
    Q8blockx(xs::Vector{T}, ys::Vector{T}) where {T<:Number, IT<:Integer}

Graded mesh of a 2-D block of Q8 finite elements.
"""
function Q8blockx(xs::Vector{T}, ys::Vector{T}) where {T<:Number}
    fens, fes = Q4blockx(xs, ys)
    fens, fes = Q4toQ8(fens, fes)
end

"""
    Q4refine(fens::FENodeSet, fes::FESetQ4)

Refine a mesh of quadrilaterals by bisection.
"""
function Q4refine(fens::FENodeSet, fes::FESetQ4)
    nedges = 4
    ec = [1 2; 2 3; 3 4; 4 1]
    # make a search structure for edges
    # Additional node numbers are numbered from here
    newn = count(fens) + 1
    # make a search structure for edges
    edges = makecontainer()
    for i in eachindex(fes.conn)
        for J in 1:nedges
            ev = fes.conn[i][ec[J, :]]
            newn = addhyperface!(edges, ev, newn)
        end
    end
    newn = newn + length(fes.conn) # add the interior nodes to the total
    xyz1 = fens.xyz             # Pre-existing nodes
    # Allocate for vertex nodes plus edge nodes plus face nodes
    xyz = zeros(eltype(xyz1), newn - 1, size(xyz1, 2))
    xyz[1:size(xyz1, 1), :] = xyz1 # existing nodes are copied over
    # calculate the locations of the new nodes
    # and construct the new nodes
    for i in keys(edges)
        C = edges[i]
        for J in eachindex(C)
            ix = vec([item for item in C[J].o])
            push!(ix, i)
            xyz[C[J].n, :] = mean(xyz[ix, :], dims = 1)
        end
    end
    # construct new geometry cells: for new elements out of one old one
    nconn = zeros(Int, 4 * length(fes.conn), 4)
    nc = 1
    for i in eachindex(fes.conn)
        econn = zeros(Int, 1, nedges)
        for J in 1:nedges
            ev = fes.conn[i][ec[J, :]]
            h, n = findhyperface!(edges, ev)
            econn[J] = n
        end

        inn = size(xyz, 1) - length(fes.conn) + i

        xyz[inn, :] = mean(xyz[[k for k in fes.conn[i]], :], dims = 1) # interior node
        #h,inn=findhyperface!(faces, conn);
        nconn[nc, :] = [fes.conn[i][1] econn[1] inn econn[4]]
        nc = nc + 1
        nconn[nc, :] = [fes.conn[i][2] econn[2] inn econn[1]]
        nc = nc + 1
        nconn[nc, :] = [fes.conn[i][3] econn[3] inn econn[2]]
        nc = nc + 1
        nconn[nc, :] = [fes.conn[i][4] econn[4] inn econn[3]]
        nc = nc + 1
    end
    fens = FENodeSet(xyz)
    nfes = FESetQ4(nconn)
    return fens, nfes            # I think I should not be overwriting the input!
end

"""
    Q9blockx(xs::Vector{T}, ys::Vector{T}) where {T<:Number}

Create a block of the quadratic Lagrangean Q9 nine-node quadrilaterals.
"""
function Q9blockx(xs::Vector{T}, ys::Vector{T}) where {T<:Number}
    fens, fes = Q4blockx(xs, ys)
    nedges = 4
    ec = [1 2; 2 3; 3 4; 4 1]
    # make a search structure for edges
    # Additional node numbers are numbered from here
    newn = count(fens) + 1
    # make a search structure for edges
    edges = makecontainer()
    for i in eachindex(fes.conn)
        for J in 1:nedges
            ev = fes.conn[i][ec[J, :]]
            newn = addhyperface!(edges, ev, newn)
        end
    end
    newn = newn + length(fes.conn) # add the interior nodes to the total
    xyz1 = fens.xyz             # Pre-existing nodes
    # Allocate for vertex nodes plus edge nodes plus face nodes
    xyz = zeros(T, newn - 1, size(xyz1, 2))
    xyz[1:size(xyz1, 1), :] = xyz1 # existing nodes are copied over
    # calculate the locations of the new nodes
    # and construct the new nodes
    for i in keys(edges)
        C = edges[i]
        for J in eachindex(C)
            ix = vec([item for item in C[J].o])
            push!(ix, i)
            xyz[C[J].n, :] = mean(xyz[ix, :], dims = 1)
        end
    end
    # construct new geometry cells: for new elements out of one old one
    nconn = zeros(Int, length(fes.conn), 9)
    nc = 1
    for i in eachindex(fes.conn)
        econn = zeros(Int, 1, nedges)
        for J in 1:nedges
            ev = fes.conn[i][ec[J, :]]
            h, n = findhyperface!(edges, ev)
            econn[J] = n
        end

        inn = size(xyz, 1) - length(fes.conn) + i

        xyz[inn, :] = mean(xyz[[k for k in fes.conn[i]], :], dims = 1) # interior node

        nconn[nc, :] = hcat(fes.conn[i]..., econn..., inn)
        nc = nc + 1
    end
    fens = FENodeSet(xyz)
    nfes = FESetQ9(nconn)
    return fens, nfes
end

"""
    Q8annulus(rin::T, rex::T, nr::IT, nc::IT, Angl::T) where {T<:Number, IT<:Integer}

Mesh of an annulus segment.

Mesh of an annulus segment, centered at the origin, with internal radius
rin`, and  external radius `rex`, and  development angle Angl. Divided into
elements: `nr`, `nc` in the radial and circumferential direction
respectively.
"""
function Q8annulus(rin::T, rex::T, nr::IT, nc::IT, Angl::T) where {T<:Number, IT<:Integer}
    trin = min(rin, rex)
    trex = max(rin, rex)
    fens, fes = Q8block(trex - trin, Angl, nr, nc)
    xy = fens.xyz
    for i in eachindex(fens)
        r = trin + xy[i, 1]
        a = xy[i, 2]
        xy[i, :] = [r * cos(a) r * sin(a)]
    end
    fens.xyz = xy
    return fens, fes
end

function _ontosphere!(xyz, radius)
    for j in axes(xyz, 1)
        xyz[j, :] = xyz[j, :] * radius / norm(xyz[j, :])
    end
end

"""
    Q4spheren(radius::T, nperradius::IT) where {T<:Number, IT<:Integer}

Generate mesh of a spherical surface (1/8th of the sphere).
"""
function Q4spheren(radius::T, nperradius::IT) where {T<:Number, IT<:Integer}
    if (mod(nperradius, 2) != 0)
        nperradius = nperradius + 1
    end
    nL = Int(nperradius / 2)
    nW = Int(nperradius / 2)
    tolerance = radius / nperradius / 100
    a = sqrt(2.0) / 2
    b = 1 / sqrt(3.0)
    c = 0.6 * a
    d = 0.6 * b
    xyz = [1 0 0; 0 1 0; 0 0 1; a a 0; 0 a a; a 0 a; b b b]
    conn = [1 4 7 6; 4 2 5 7; 3 6 7 5]
    fens, fes = Q4quadrilateral(xyz[conn[1, :], :], nL, nW)
    fens1, fes1 = Q4quadrilateral(xyz[conn[2, :], :], nL, nW)
    fens, fes1, fes2 = mergemeshes(fens1, fes1, fens, fes, tolerance)
    fes = cat(fes1, fes2)
    fens1, fes1 = Q4quadrilateral(xyz[conn[3, :], :], nL, nW)
    fens, fes1, fes2 = mergemeshes(fens1, fes1, fens, fes, tolerance)
    fes = cat(fes1, fes2)
    _ontosphere!(fens.xyz, radius)
    return fens, fes
end


"""
    Q4circlen(radius::T, nperradius::IT) where {T<:Number, IT<:Integer}

Mesh of a quarter circle with a given number of elements per radius.

The parameter `nperradius` should be an even 
number; if that isn't so is adjusted to by adding one. 
"""
function Q4circlen(radius::T, nperradius::IT) where {T<:Number, IT<:Integer}
    fens, fes = Q4spheren(radius, nperradius)
    # % apply transformation to project the locations of the nodes into the
    # % plane x-y
    for j in eachindex(fens)
        r = norm(fens.xyz[j, 3])
        fens.xyz[j, 1:2] = fens.xyz[j, 1:2] * ((radius - r) + r / 2) / radius
        fens.xyz[j, 3] = 0.0
    end
    return fens, fes
end


function _doextrude(fens, fes::FESetL2, nLayers, extrusionh)
    nn1 = count(fens)
    nnt = nn1 * nLayers
    ngc = count(fes) * nLayers
    qconn = zeros(Int, ngc, 4)
    conn = connasarray(fes)
    nnpe = size(conn, 2)
    xyz = zeros(eltype(fens.xyz), nn1 * (nLayers + 1), size(fens.xyz, 2))
    x1 = fill(0.0, size(fens.xyz, 2))
    for j in 1:nn1
        x1[:] .= fens.xyz[j, :]
        xyz[j, :] .= extrusionh(x1, 0)
    end
    for k in 1:nLayers
        for j in 1:nn1
            x1[:] .= fens.xyz[j, :]
            f = j + k * nn1
            xyz[f, :] .= extrusionh(x1, k)
        end
    end

    gc = 1
    for k in 1:nLayers
        for i in eachindex(fes)
            for n in 1:nnpe
                qconn[gc, n] = conn[i, n] + (k - 1) * nn1
            end
            for n in 1:nnpe
                qconn[gc, n+nnpe] = conn[i, nnpe+1-n] + (k) * nn1
            end
            gc = gc + 1
        end
    end
    efes = FESetQ4(qconn)
    efens = FENodeSet(xyz)
    return efens, efes
end


"""
    Q4extrudeL2(
        fens::FENodeSet,
        fes::FESetL2,
        nLayers::IT,
        extrusionh::F,
    ) where {F<:Function, IT<:Integer}

Extrude a mesh of linear segments into a mesh of quadrilaterals (Q4).
"""
function Q4extrudeL2(
    fens::FENodeSet,
    fes::FESetL2,
    nLayers::IT,
    extrusionh::F,
) where {F<:Function, IT<:Integer}
    id = vec([i for i in eachindex(fens)])
    cn = connectednodes(fes)
    id[cn[:]] = vec([i for i in eachindex(cn)])
    l2fes = deepcopy(fes)
    updateconn!(l2fes, id)
    l2fens = FENodeSet(fens.xyz[cn[:], :])
    return _doextrude(l2fens, l2fes, nLayers, extrusionh)
end


end
