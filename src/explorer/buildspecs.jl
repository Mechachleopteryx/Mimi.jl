## Mimi UI
using Dates
using CSVFiles

function dataframe_or_scalar(m::Model, comp_name::Symbol, item_name::Symbol)
    dims = dimensions(m, comp_name, item_name)
    return length(dims) > 0 ? getdataframe(m, comp_name, item_name) : m[comp_name, item_name]
end

# Generate the VegaLite spec for a variable or parameter
function _spec_for_item(m::Model, comp_name::Symbol, item_name::Symbol; interactive::Bool=true)
    dims = dimensions(m, comp_name, item_name)

    # Control flow logic selects the correct plot type based on dimensions
    # and dataframe fields
    if length(dims) == 0
        value = m[comp_name, item_name]
        name = "$comp_name : $item_name = $value"
        spec = createspec_singlevalue(name)
    elseif length(dims) > 2
        @warn("$comp_name.$item_name has >2 graphing dims, not yet implemented in explorer")
        return nothing
    else
        name = "$comp_name : $item_name"          
        df = getdataframe(m, comp_name, item_name)

        dffields = map(string, names(df))         # convert to string once before creating specs

        # check if there are too many dimensions to map and if so, error
        if length(dffields) > 3
            error()
                
        # a 'time' field necessitates a line plot  
        elseif dffields[1] == "time"
            if length(dffields) > 2
                spec = createspec_multilineplot(name, df, dffields, interactive=interactive)
            else
                spec = createspec_lineplot(name, df, dffields, interactive=interactive)
            end
        
        #otherwise we are dealing with a barplot
        else
            spec = createspec_barplot(name, df, dffields)
        end
    end

    return spec
        
end

function _spec_for_sim_item(sim_inst::SimulationInstance, comp_name::Symbol, item_name::Symbol; model_index::Int = 1, scen_name::Union{Nothing, String} = nothing, interactive::Bool=true)
    
    multiple_results = (length(sim_inst.results) > 1)

    # get results
    key = (comp_name, item_name)
    df = (sim_inst.results[model_index])[key]
    if scen_name !== nothing
        if in(:scen, names(df)) 
            error("The results for this simulation contain a scenario dimension, you must specify the scen_name keyword argument, which is currently set to $(scen_name)")
        end
        filter!(row -> row.scen_name === scen_name, df)
    end

    # Control flow logic selects the correct plot type based on dimensions
    # and dataframe fields
    m = sim_inst.models[model_index]
    dims = dimensions(m, comp_name, item_name)
    dffields = map(string, names(df))         # convert to string once before creating specs

    if length(dims) == 0 # histogram
        spec = createspec_histogram(name, df, dffields)
    elseif length(dims) > 2
        @warn("$comp_name.$item_name has >2 graphing dims, not yet implemented in explorer")
        return nothing
    else
        name = "$comp_name : $item_name"          

        # check if there are too many dimensions to map and if so, error
        if length(dffields) > 4
            error()
                
        # a 'time' field necessitates a trumpet plot
        elseif dffields[1] == "time"
            if length(dffields) > 3
                spec =createspec_multitrumpet(name, df, dffields; interactive = interactive)
            else
                spec = createspec_trumpet(name, df, dffields; interactive = interactive)
            end
        #otherwise we are dealing with layered histograms
        else
            spec = createspec_multihistogram(name, df, dffields)
        end
    end
    
    return spec
        
end

# Create menu item
function _menu_item(m::Model, comp_name::Symbol, item_name::Symbol)
    dims = dimensions(m, comp_name, item_name)

    if length(dims) == 0
        value = m[comp_name, item_name]
        name = "$comp_name : $item_name = $value"
    elseif length(dims) > 2
        @warn("$comp_name.$item_name has >2 graphing dims, not yet implemented in explorer")
        return nothing
    else
        name = "$comp_name : $item_name"          # the name is needed for the list label
    end

    menu_item = Dict("name" => name, "comp_name" => comp_name, "item_name" => item_name)
    return menu_item
end

function _menu_item(sim_inst::SimulationInstance, datum_key::Tuple{Symbol, Symbol})
    (comp_name, item_name) = datum_key
    dims = dimensions(sim_inst.models[1], comp_name, item_name)
    if length(dims) > 2
        @warn("$comp_name.$item_name has >2 graphing dims, not yet implemented in explorer")
        return nothing
    else
        name = "$comp_name : $item_name"          # the name is needed for the list label
    end

    menu_item = Dict("name" => "$item_name", "comp_name" => comp_name, "item_name" => item_name)
    return menu_item
end

# Create the list of variables and parameters
function menu_item_list(model::Model)
    all_menuitems = []

    for comp_name in map(name, compdefs(model)) 
        items = vcat(variable_names(model, comp_name), parameter_names(model, comp_name))

        for item_name in items
            menu_item = _menu_item(model, comp_name, item_name)
            if menu_item !== nothing
                push!(all_menuitems, menu_item) 
            end
        end
    end

    # Return sorted list so that the UI list of items will be in alphabetical order 
    return sort(all_menuitems, by = x -> lowercase(x["name"]))
end

# Create the list of variables and parameters
function menu_item_list(sim_inst::SimulationInstance)
    all_menuitems = []
    for datum_key in sim_inst.sim_def.savelist

        menu_item = _menu_item(sim_inst, datum_key)
        if menu_item !== nothing
            push!(all_menuitems, menu_item) 
        end
    end

    # Return sorted list so that the UI list of items will be in alphabetical order 
    return sort(all_menuitems, by = x -> lowercase(x["name"]))
end

# So we can control these in one place...
global const _plot_width  = 450
global const _plot_height = 410
global const _slider_height = 90

# Create individual specs for exploring a model
function createspec_lineplot(name, df, dffields; interactive::Bool=true)
    interactive ? createspec_lineplot_interactive(name, df, dffields) : createspec_lineplot_static(name, df, dffields)
end
 
function createspec_lineplot_interactive(name, df, dffields)
    datapart = getdatapart(df, dffields, :line) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "type" => "line",
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v2.0.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "vconcat" => [
                Dict(
                    "transform" => [Dict("filter" => Dict("selection" => "brush"))],
                    "width" => _plot_width,
                    "height" => _plot_height,
                    "mark" => Dict("type" => "line", "point" => true),
                    "encoding" => Dict(
                        "x" => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear", 
                            "axis" => Dict("title"=> "")
                        ),             
                        "y" => Dict(
                            "field" => dffields[2], 
                            "type" => "quantitative",
                        )
                    )
                ), Dict(
                    "width" => _plot_width,
                    "height" => _slider_height,
                    "mark" => Dict("type" => "line", "point" => true),
                    "selection" => Dict("brush" => Dict("type" => "interval", "encodings" => ["x"])),
                    "encoding" => Dict(
                        "x" => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear"
                        ),
                        "y" => Dict(
                            "field" => dffields[2], 
                            "type" => "quantitative",
                            "axis" => Dict("tickCount" => 3, "grid" => false
                            )
                        )
                    )
                )
            ]
        )
    )
    return spec
end

function createspec_lineplot_static(name, df, dffields)
    datapart = getdatapart(df, dffields, :line) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "type" => "line",
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v2.0.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "mark" => Dict("type" => "line"),
            "encoding" => Dict(
                "x" => Dict(
                    "field" => dffields[1], 
                    "type" => "temporal", 
                    "timeUnit" => "utcyear", 
                ),             
                "y" => Dict(
                    "field" => dffields[2], 
                    "type" => "quantitative",
                )
            ),
            "width" => _plot_width,
            "height" => _plot_height,
        )
    )
    return spec
end

function createspec_multilineplot(name, df, dffields; interactive::Bool=true)
    interactive ? createspec_multilineplot_interactive(name, df, dffields) : createspec_multilineplot_static(name, df, dffields)
end

function createspec_multilineplot_interactive(name, df, dffields)
    datapart = getdatapart(df, dffields, :multiline) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v2.0.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"  => Dict("values" => datapart),
            "vconcat" => [
                Dict(
                    "transform" => [Dict("filter" => Dict("selection" => "brush"))],
                    "mark" => Dict("type" => "line", "point" => true),
                    "encoding" => Dict(
                        "x"     => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear", 
                            "axis" => Dict("title"=> "")
                            ),                
                        "y"     => Dict(
                            "field" => dffields[3], 
                            "type" => "quantitative",
                            ),
                        "color" => Dict("field" => dffields[2], "type" => "nominal", 
                            "scale" => Dict("scheme" => "category20")),
                    ),
                    "width"  => _plot_width,
                    "height" => _plot_height
                ), Dict(
                    "width" => _plot_width,
                    "height" => _slider_height,
                    "mark" => Dict("type" => "line", "point" => true),
                    "selection" => Dict("brush" => Dict("type" => "interval", "encodings" => ["x"])),
                    "encoding" => Dict(
                        "x" => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear"
                        ),
                        "y" => Dict(
                            "field" => dffields[3], 
                            "type" => "quantitative",
                            "axis" => Dict("tickCount" => 3, "grid" => false)
                        ),
                        "color" => Dict("field" => dffields[2], "type" => "nominal", 
                            "scale" => Dict("scheme" => "category20")
                        )
                    )
                )
            ]
        ),
    )
    return spec
end

function createspec_multilineplot_static(name, df, dffields)
    datapart = getdatapart(df, dffields, :multiline) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v2.0.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"  => Dict("values" => datapart),
    
            "mark" => Dict("type" => "line"),
            "encoding" => Dict(
                "x"     => Dict(
                    "field" => dffields[1], 
                    "type" => "temporal", 
                    "timeUnit" => "utcyear", 
                    ),                
                "y"     => Dict(
                    "field" => dffields[3], 
                    "type" => "quantitative",
                    ),
                "color" => Dict("field" => dffields[2], "type" => "nominal", 
                    "scale" => Dict("scheme" => "category20")),
            ),
            "width"  => _plot_width,
            "height" => _plot_height
        ),
    )
    return spec
end

function createspec_barplot(name, df, dffields)
    datapart = getdatapart(df, dffields, :bar) #returns JSONtext type     
    spec = Dict(
        "name"  => name,
        "type" => "bar",
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v2.0.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "mark" => "bar",
            "encoding" => Dict(
                "x" => Dict("field" => dffields[1], "type" => "ordinal"),
                "y" => Dict("field" => dffields[2], "type" => "quantitative" )
                ),
            "width"  => _plot_width,
            "height" => _plot_height 
        )
    )
    return spec
end

function createspec_singlevalue(name)

    datapart = [];
    spec = Dict(
        "name" => name, 
        "type" => "singlevalue",
        "VLspec" => Dict()
    )
    return spec
end

# Create individual specs for exploring a Simulation
function createspec_trumpet(name, df, dffields; interactive::Bool=true)
    df_reduced = trumpet_df_reduce(df, :trumpet) #reduce the dataframe down to only the data needed for max, min, and mean lines
    interactive ? createspec_trumpet_interactive(name, df_reduced, dffields) : createspec_trumpet_static(name, df_reduced, dffields)
end

# https://vega.github.io/vega-lite/examples/layer_line_errorband_ci.html
function createspec_trumpet_static(name, df, dffields)

    datapart = getdatapart(df, dffields, :trumpet) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v3.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "encoding" => Dict(
                "x"     => Dict(
                    "field" => dffields[1], 
                    "type" => "temporal", 
                    "timeUnit" => "utcyear", 
                )
            ),
            "layer" => [
                Dict(
                    "mark" => "line",
                    "encoding" => Dict(
                        "y" => Dict(
                            "aggregate" => "mean", 
                            "field" => dffields[2],
                            "type" => "quantitative"
                        )
                    )
                ),
                Dict(
                    "mark" => "area",
                    "encoding" => Dict(
                        "y" => Dict(
                            "aggregate" => "max", 
                            "field" => dffields[2],
                            "type" => "quantitative",
                            "title" => "$(dffields[2])"
                        ),
                        "y2" => Dict(
                            "aggregate" => "min", 
                            "field" => dffields[2],
                        ),
                        "opacity" => Dict(
                            "value" => 0.5
                        )
                    )
                )

            ]
        ),
        "width"  => _plot_width,
        "height" => _plot_height
    )
    return spec
end

function createspec_trumpet_interactive(name, df, dffields)

    datapart = getdatapart(df, dffields, :trumpet) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v3.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "vconcat" => [
                Dict(
                    "width" => _plot_width,
                    "height" => _plot_height,
                    "encoding" => Dict(
                        "x"     => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear", 
                            "scale" => Dict("domain" => Dict("selection" => "brush"))
                        )
                    ),
                    "layer" => [
                        Dict(
                            "mark" => "line",
                            "encoding" => Dict(
                                "y" => Dict(
                                    "aggregate" => "mean", 
                                    "field" => dffields[2],
                                    "type" => "quantitative"
                                )
                            )
                        ),
                        Dict(
                            "mark" => "area",
                            "encoding" => Dict(
                                "y" => Dict(
                                    "aggregate" => "max", 
                                    "field" => dffields[2],
                                    "type" => "quantitative",
                                    "title" => "$(dffields[2])"
                                ),
                                "y2" => Dict(
                                    "aggregate" => "min", 
                                    "field" => dffields[2],
                                ),
                                "opacity" => Dict(
                                    "value" => 0.5
                                )
                            )
                        )
        
                    ]
                ),
                Dict(
                    "width" => _plot_width,
                    "height" => _slider_height,
                    "encoding" => Dict(
                        "x"     => Dict(
                            "field" => dffields[1], 
                            "type" => "temporal", 
                            "timeUnit" => "utcyear", 
                        )
                    ),

                    "layer" => [
                        Dict(
                            "mark" => "line",
                            "encoding" => Dict(
                                "y" => Dict(
                                    "aggregate" => "mean", 
                                    "field" => dffields[2],
                                    "type" => "quantitative"
                                )
                            )
                        ),
                        Dict(
                            "mark" => "area",
                            "selection" => Dict("brush" => Dict("type" => "interval", "encodings" => ["x"])),
                            "encoding" => Dict(
                                "y" => Dict(
                                    "aggregate" => "max", 
                                    "field" => dffields[2],
                                    "type" => "quantitative",
                                    "title" => "$(dffields[2])"
                                ),
                                "y2" => Dict(
                                    "aggregate" => "min", 
                                    "field" => dffields[2],
                                ),
                                "opacity" => Dict(
                                    "value" => 0.5
                                )
                            )
                        )
        
                    ]
                )
            ]
        )
    )
    return spec
end

function createspec_multitrumpet(name, df, dffields; interactive::Bool = true)
    df_reduced = trumpet_df_reduce(df, :multitrumpet) #reduce the dataframe down to only the data needed for max, min, and mean lines
    interactive ? createspec_multitrumpet_interactive(name, df, dffields) : createspec_multitrumpet_static(name, df, dffields)
end

function createspec_multitrumpet_interactive(name, df, dffields)
    datapart = getdatapart(df, dffields, :multitrumpet) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v3.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data"=> Dict("values" => datapart),
            "facet" => Dict("row" => Dict("field" => dffields[2], "type" => "nominal")),
            "spec" => Dict(
                "vconcat" => [
                    Dict(
                        "width" => _plot_width,
                        "height" => _plot_height,
                        "encoding" => Dict(
                            "x"     => Dict(
                                "field" => dffields[1], 
                                "type" => "temporal", 
                                "timeUnit" => "utcyear", 
                                "scale" => Dict("domain" => Dict("selection" => "brush"))
                            )
                        ),
                        "layer" => [
                            Dict(
                                "mark" => "line",
                                "encoding" => Dict(
                                    "y" => Dict(
                                        "aggregate" => "mean", 
                                        "field" => dffields[3],
                                        "type" => "quantitative"
                                    )
                                )
                            ),
                            Dict(
                                "mark" => "area",
                                "encoding" => Dict(
                                    "y" => Dict(
                                        "aggregate" => "max", 
                                        "field" => dffields[3],
                                        "type" => "quantitative",
                                        "title" => "$(dffields[3])"
                                    ),
                                    "y2" => Dict(
                                        "aggregate" => "min", 
                                        "field" => dffields[3],
                                    ),
                                    "opacity" => Dict(
                                        "value" => 0.5
                                    )
                                )
                            )
            
                        ]
                    ),
                    Dict(
                        "width" => _plot_width,
                        "height" => _slider_height,
                        "encoding" => Dict(
                            "x"     => Dict(
                                "field" => dffields[1], 
                                "type" => "temporal", 
                                "timeUnit" => "utcyear", 
                            )
                        ),

                        "layer" => [
                            Dict(
                                "mark" => "line",
                                "encoding" => Dict(
                                    "y" => Dict(
                                        "aggregate" => "mean", 
                                        "field" => dffields[2],
                                        "type" => "quantitative"
                                    )
                                )
                            ),
                            Dict(
                                "mark" => "area",
                                "selection" => Dict("brush" => Dict("type" => "interval", "encodings" => ["x"])),
                                "encoding" => Dict(
                                    "y" => Dict(
                                        "aggregate" => "max", 
                                        "field" => dffields[3],
                                        "type" => "quantitative",
                                        "title" => "$(dffields[3])"
                                    ),
                                    "y2" => Dict(
                                        "aggregate" => "min", 
                                        "field" => dffields[3],
                                    ),
                                    "opacity" => Dict(
                                        "value" => 0.5
                                    )
                                )
                            )
            
                        ]
                    )
                ]
            )
        )
    )
    return spec
end

function createspec_multitrumpet_static(name, df, dffields)
    datapart = getdatapart(df, dffields, :multitrumpet) #returns JSONtext type 
    spec = Dict(
        "name"  => name,
        "VLspec" => Dict(
            "\$schema" => "https://vega.github.io/schema/vega-lite/v3.json",
            "description" => "plot for a specific component variable pair",
            "title" => name,
            "data" => Dict("values" => datapart),
            "facet" => Dict("row" => Dict("field" => dffields[2], "type" => "nominal")),
            "spec" => Dict(
                "encoding" => Dict(
                    "x"     => Dict(
                        "field" => dffields[1], 
                        "type" => "temporal", 
                        "timeUnit" => "utcyear", 
                    )
                ),
                "layer" => [
                    Dict(
                        "mark" => "line",
                        "encoding" => Dict(
                            "y" => Dict(
                                "aggregate" => "mean", 
                                "field" => dffields[3],
                                "type" => "quantitative"
                            )
                        )
                    ),
                    Dict(
                        "mark" => "area",
                        "encoding" => Dict(
                            "y" => Dict(
                                "aggregate" => "max", 
                                "field" => dffields[3],
                                "type" => "quantitative",
                                "title" => "$(dffields[3])"
                            ),
                            "y2" => Dict(
                                "aggregate" => "min", 
                                "field" => dffields[3],
                            ),
                            "opacity" => Dict(
                                "value" => 0.5
                            )
                        )
                    )

                ]
            )
        ),
        "width"  => _plot_width,
        "height" => _plot_height
    )
    return spec
end

function createspec_histogram(name, df, dffields)
    # TODO
    return nothing
end

function createspec_multihistogram(name, df, dffields)
    # TODO
    return nothing
end

# Helper functions to get JSONtext of the data
function getdatapart(df, dffields, plottype::Symbol)

    sb = StringBuilder()
    append!(sb, "[");

    # loop over rows and create a dictionary for each row
    if plottype == :multitrumpet
        cols = (df[1], df[2], df[3], df[4])
        datastring = getmultitrumpet(cols, dffields)
    elseif plottype == :multiline || plottype == :trumpet
        cols = (df[1], df[2], df[3])
        datastring = getmultiline(cols, dffields)
    elseif plottype == :line
        cols = (df[1], df[2])
        datastring = getline(cols, dffields)
    else
        cols = (df[1], df[2])
        datastring = getbar(cols, dffields)
    end

    append!(sb, datastring * "]");
    datapart = String(sb)

    return JSON.JSONText(datapart)
end

function getmultiline(cols, dffields)
    datasb = StringBuilder()
    numrows = length(cols[1])
    for i = 1:numrows

        append!(datasb, "{\"" * dffields[1]  * "\":\"" * string(Date(cols[1][i]))
            * "\",\"" * dffields[2] * "\":\"" * string(cols[2][i]) * "\",\"" 
            * dffields[3] * "\":\"" * string(cols[3][i]) * "\"}")
        
        if i != numrows
            append!(datasb, ",")
        end  
    end
    return String(datasb)
end

function getmultitrumpet(cols, dffields)
    datasb = StringBuilder()
    numrows = length(cols[1])
    for i = 1:numrows

        append!(datasb, "{
            \"" * dffields[1]  * "\":\"" * string(Date(cols[1][i])) * "\",
            \"" * dffields[2] * "\":\"" * string(cols[2][i]) * "\",
            \"" * dffields[3] * "\":\"" * string(cols[3][i]) * "\",
            \"" * dffields[4] * "\":\"" * string(cols[4][i]) * "\",
            }")
        
        if i != numrows
            append!(datasb, ",")
        end  
    end
    return String(datasb)
end

function getline(cols, dffields)
    datasb = StringBuilder()
    numrows = length(cols[1])
    for i = 1:numrows
        append!(datasb, "{\"" * dffields[1]  * "\":\"" * string(Date(cols[1][i])) 
            * "\",\"" * dffields[2] * "\":\"" * string(cols[2][i]) * "\"}") 

        if i != numrows
            append!(datasb, ",")
        end
    end
    
    return String(datasb)
end

function getbar(cols, dffields)
    datasb = StringBuilder()
    numrows = length(cols[1])
    for i = 1:numrows

        append!(datasb, "{\"" * dffields[1] * "\":\"" * string(cols[1][i]) *
            "\",\"" * dffields[2] * "\":\"" * string(cols[2][i]) * "\"}") #end of dictionary

        if i != numrows
            append!(datasb, ",")
        end
    end
    return String(datasb)
end

function trumpet_df_reduce(df, plottype::Symbol)
    
    if plottype == :trumpet
        col_index = 2
    else
        col_index = 3
    end

    col = names(df)[col_index]
    groupby_keys = []
    for i = 1:length(names(df))
        i != col_index && push!(groupby_keys,  names(df)[i])
    end

    df_new = by(df, groupby_keys, value = col => minimum)
    append!(df_new, by(df, groupby_keys, value = col => maximum))
    append!(df_new, by(df, groupby_keys, value = col => mean))
    rename!(df_new, :value => col)

    if plottype == :trumpet
        reorder_cols = [groupby_keys[1], col, groupby_keys[2:end]...]
    else
        reorder_cols = [groupby_keys[1:2]..., col, groupby_keys[3:end]...]
    end

    return df_new[reorder_cols]
end