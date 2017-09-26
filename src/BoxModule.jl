"""
    BoxModule

Module for working with bounding boxes.
"""
module BoxModule

export inbox, initbox!, updatebox!, boundingbox, inflatebox!, boxesoverlap

using FinEtools
using FinEtools.FTypesModule



"""
    inbox(box::AbstractVector, x::AbstractVector)

Is the given location inside the box.

Note: point on the boundary of the box is counted as being inside.
"""
function inbox(box::AbstractVector, x::AbstractVector)
    inrange(rangelo,rangehi,r) = ((r>=rangelo) && (r<=rangehi));
    sdim=length(x);
    @assert 2*sdim == length(box)
    b = inrange(box[1], box[2], x[1]);
    for i=2:sdim
        b = (b && inrange(box[2*i-1], box[2*i], x[i]));
    end
    return b
end

function inbox(box::AbstractVector, x::AbstractArray)
    return inbox(box, vec(x))
end

"""
    initbox!(box::AbstractVector, x::AbstractVector)

Initialize a bounding box with a single point.
"""
function initbox!(box::AbstractVector, x::AbstractVector)
    sdim = length(x)
    if length(box) < 2*sdim
        box = Array{FFlt}(2*sdim)
    end
    for i = 1:sdim
        box[2*i-1] = box[2*i] = x[i];
    end
    return box
end

"""
    updatebox!(box::AbstractVector, x::AbstractArray)

Update a box with another location, or create a new box.

If the  `box` does not have  the correct dimensions,  it is correctly sized.

`box` = bounding box
    for 1-D `box=[minx,maxx]`, or
    for 2-D `box=[minx,maxx,miny,maxy]`, or
    for 3-D `box=[minx,maxx,miny,maxy,minz,maxz]`
    The `box` is expanded to include the
    supplied location `x`.   The variable `x`  can hold multiple points in rows.
"""
function updatebox!(box::AbstractVector, x::AbstractArray)
    sdim = size(x,2)
    if length(box) < 2*sdim
        box = Array{FFlt}(2*sdim)
        for i = 1:size(x,2)
            box[2*i-1] = Inf;
            box[2*i]   = -Inf;
        end
    end
    for j = 1:size(x,1)
        for i = 1:sdim
            box[2*i-1] = min(box[2*i-1],x[j,i]);
            box[2*i]   = max(box[2*i],x[j,i]);
        end
    end
    return box
end

function updatebox!(box::AbstractVector, x::AbstractVector)
    return updatebox!(box, reshape(x, 1, length(x)))
end

"""
    boundingbox(x::AbstractArray)

Compute the bounding box of the points in `x`.

`x` = holds points, one per row.

Returns `box` = bounding box
    for 1-D `box=[minx,maxx]`, or
    for 2-D `box=[minx,maxx,miny,maxy]`, or
    for 3-D `box=[minx,maxx,miny,maxy,minz,maxz]`
"""
function boundingbox(x::AbstractArray)
    return updatebox!(Array{FFlt}(0), x)
end

function inflatebox!(box::AbstractVector, inflatevalue::Number)
    abox = deepcopy(box)
    sdim = Int(length(box)/2);
    for i=1:sdim
        box[2*i-1] = min(abox[2*i-1],abox[2*i]) - inflatevalue;
        box[2*i]   = max(abox[2*i-1],abox[2*i]) + inflatevalue;
    end
    return box
end

"""
    boxesoverlap(box1::AbstractVector, box2::AbstractVector)

Do the given boxes overlap?
"""
function boxesoverlap(box1::AbstractVector, box2::AbstractVector)
    dim=Int(length(box1)/2);
    @assert 2*dim == length(box2) "Mismatched boxes"
    for i=1:dim
        if box1[2*i-1]>box2[2*i]
            return false;
        end
        if box1[2*i]<box2[2*i-1]
            return false;
        end
    end
    return  true;
end

end
