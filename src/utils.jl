# Save and recover colormaps

function cgrad_to_csv(csvfile::AbstractString, cgrad::PlotUtils.ColorGradient)
    values = cgrad.values
    colors = cgrad.colors.colors

    reds = Colors.red.(colors)
    greens = Colors.green.(colors)
    blues = Colors.blue.(colors)
    alphas = Colors.alpha.(colors)
    
    csv_matrix = hcat(values, reds, greens, blues, alphas)
    csv_matrix_with_headers = vcat(["Value" "Red" "Green" "Blue" "Alpha"], csv_matrix)

    DelimitedFiles.writedlm(csvfile, csv_matrix_with_headers, ',')
end

function csv_to_cgrad(csvfile::AbstractString)
    data_cells, header_cells = DelimitedFiles.readdlm(csvfile, ',', Float64, '\n'; header = true)
    return PlotUtils.cgrad(RGBAf.(data_cells[:, 2], data_cells[:, 3], data_cells[:, 4]), data_cells[:, 1])
end


# Postprocessing utils for printing

# Convert colors from RGB to CMYK in the given PDF
# This should help the green tint which is issued when printing,
# and provide greater colour accuracy.
"""
    rgb_to_cmyk_pdf(source_file::AbstractString, dest_file::AbstractString)

Runs Ghostscript on `source_file` to convert its color schema from RGB to CMYK,
and stores the result in `dest_file`.

This works well when preparing a PDF for printing, since many printer drivers
don't perform the conversion as well as Ghostscript does.  You might see a 
green tint on black when printing in color; this ameliorates that to a large degree.

!!! note
    Converting from RGB to CMYK is a lossy operation, since CMYK is a strict subset of RGB.
"""
function rgb_to_cmyk_pdf(source_file::AbstractString, dest_file::AbstractString)
    Ghostscript_jll.gs() do gs
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                run(`gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sColorConversionStrategy=CMYK -sOutputFile=$(dest_file) $(source_file)`)
            end
        end
    end
end

"""
    searchsortednearest(a, x)

Returns the index of the nearest element to `x` in `a`.
`a` must be a sorted array, and its elements must be mathematically interoperable with `x`.  
"""
function searchsortednearest(a,x)
    idx = searchsortedfirst(a,x)

    (idx==1)        && return idx
    (idx>length(a)) && return length(a)
    (a[idx]==x)     && return idx

    if (abs(a[idx]-x) < abs(a[idx-1]-x))
       return idx
    else
       return idx-1
    end
end



# Taken from Plots.jl
function compute_gridsize(numplts::Int; landscape = false, nr = -1, nc = -1)
    # figure out how many rows/columns we need
    if nr < 1
        if nc < 1
            nr = round(Int, sqrt(numplts))
            nc = ceil(Int, numplts / nr)
        else
            nr = ceil(Int, numplts / nc)
        end
    else
        nc = ceil(Int, numplts / nr)
    end
    if landscape
        return min(nr, nc), max(nr, nc)
    else
        return max(nr, nc), min(nr, nc)
    end
end

compute_gridsize((nr, nc); landscape = false) = (nr, nc)



# Rasters.jl - convenience

function resample_file(file, to_raster::Rasters.AbstractRaster, crop_geom)
    raster = Rasters.Raster(file; lazy = true)

    cropped_raster = Rasters.crop(raster, to = crop_geom)
    resampled_raster = Rasters.resample(cropped_raster, to=to_raster, method = :average)
    original_bounds = bounds(raster)
    return Rasters.crop(resampled_raster, to=GeoInterface.Extents.Extent(X = original_bounds[1], Y = original_bounds[2]))
end


# data munging utilities for the CPHS database

"""
    get_HR_number(hr::Union{String, Missing})::Union{Int, Missing}

Extracts the number from a string of a form `"HR ???"` and returns it.
If the input is `missing`, then `missing` is returned.
"""
function get_HR_number(hr::String)
    return parse(Int, hr[(findfirst(' ', hr)+1):end])
end

get_HR_number(::Missing) = missing

# read lat-long strings from the CMIE Capex database 

"""
    latlong_string_to_points(latlong_string)

Parses a string of the form `lat1,long1 : lat2,long2 : lat3,long3 : ...` 
and returns a Vector of Point2e which define points as (long, lat).  

Is robust to cutoff errors and other potential issues.
"""
function latlong_string_to_points(latlong_string::AbstractString)

    points = Point2{Float64}[]

    pointstrings = split(latlong_string, ":")

    isempty(pointstrings) && return []

    for pointstring in pointstrings
        point = split(pointstring, ",")
        if length(point) ≤ 1 || length(point) > 2 || any(isempty.(point))
            continue
        else
            push!(points, Point2{Float64}(parse(Float64, strip(point[2])), parse(Float64, strip(point[1]))))
        end
    end

    return points

end

"""
    points_weights(latlong_strings::Vector{:< AbstractString}, costs::Vector{<: Real})

Parses strings of the form `lat1,long1 : lat2,long2 : lat3,long3 : ...` 
and returns a Vector of Point2e which define points as (long, lat), as well as
a vector of weights per point.  If the string has more than one point defined, 
the weight is spread across all `n` points such that each point has a weight of `cost[i]/n`.

Returns (::Vector{Point2e}, ::Vector{<: Real}).
    

!!! note
    This format of data is often found in CMIE capex location data.
"""
function points_weights(latlong_strings, costs)
    @assert length(latlong_strings) == length(costs)

    points = Vector{Point2{Float64}}()
    weights = Vector{Float64}()

    sizehint!(points, length(latlong_strings))
    sizehint!(weights, length(latlong_strings))

    for (latlong_string, cost) in zip(latlong_strings, costs)
        parsed_points = latlong_string_to_points(latlong_string)
        if length(parsed_points) == 1
            push!(points, parsed_points[1])
            push!(weights, cost)
        elseif length(parsed_points) > 1
            append!(points, parsed_points)
            append!(weights, fill(cost/length(parsed_points), length(parsed_points)))
        end
    end

    return points, weights
end