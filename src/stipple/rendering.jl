"""
    join_f(xx, delim = ""; pre::Function = identity, strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing)

Join elements of an iterator similar to [`join`](@ref) with additonal features
- evaluate the elements if they are callable
- preprocessing of elements, e.g. strip
- optional stripping of delimiter

Parameters:
- `xx`: Iterator
- `delim`: delimiter
- `pre`: preprocessor function that is applied to the resulting string of each element
- `stip_delimiter`: If true strips a potential delimiter at the end of a string
- `pre_delim`: preprocessor function for delimiter, if `nothing` it defaults to `pre`

### Example
```
julia> f() = "Hello,";

julia> join_f([1, f, "World,"], ",\\n", pre = strip) |> println
1,
Hello,
World

julia> f() = "hi - ";

julia> join_f([1, f, "2 "], " - ", pre = strip)
"1 - hi - 2"
```
"""
function join_f(xx, delim = ""; pre::Function = identity, strip_delimiter = true, pre_delim::Union{Function,Nothing} = nothing)
  io = IOBuffer()
  firstrun = true
  s_delim = pre_delim === nothing ? pre(delim) : pre_delim(delim)
  n_delim = ncodeunits(s_delim)
  for x in xx
      firstrun || print(io, delim)
      firstrun = false
      io2 = IOBuffer()
      print(io2, x isa Base.Callable ? x() : x)
      s = String(take!(io2))
      hasdelimiter = strip_delimiter && endswith(s, delim)
      s = pre(hasdelimiter ? s[1:end - ncodeunits(delim)] : s)
      # if delimter has been removed already don't check for pretreated delimiter
      print(io, strip_delimiter && ! hasdelimiter && endswith(s, s_delim) ? s[1:end - n_delim] : s)
  end
  String(take!(io))
end

join_f(s::AbstractString, delim = ""; kwargs...) = join_f([s], delim; kwargs...)

const RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

"""
    function rendering_mappings(mappings = Dict{String,String})

Registers additional `mappings` as Julia to Vue properties mappings  (eg `foobar` to `foo-bar`).
"""
function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

"""
    function julia_to_vue(field, mapping_keys = mapping_keys())

Converts Julia names to Vue names (eg `foobar` to `foo-bar`).
"""
function julia_to_vue(field, mapping_keys = mapping_keys()) :: String
  if in(string(field), mapping_keys)
    parts = split(RENDERING_MAPPINGS[string(field)], "-")

    if length(parts) > 1
      extraparts = map((x) -> uppercasefirst(string(x)), parts[2:end])
      string(parts[1], join(extraparts))
    else
      parts |> string
    end
  else
    field |> string
  end
end

"""
    function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}

Renders the Julia `ReactiveModel` `app` as the corresponding Vue.js JavaScript code.
"""
function Stipple.render(app::M)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    f = getfield(app, field)

    occursin(SETTINGS.private_pattern, String(field)) && continue
    f isa Reactive && f.r_mode == PRIVATE && continue

    result[julia_to_vue(field)] = Stipple.render(f, field)
  end

  vue = Dict( :el => JSONText("rootSelector"),
              :mixins => JSONText("[watcherMixin, reviveMixin]"),
              :data => merge(result, client_data(app)))
  for (f, field) in ((components, :components), (js_computed, :computed), (js_watch, :watch))
    js = join_f(f(app), ",\n    "; pre = strip)
    isempty(js) || push!(vue, field => JSONText("{\n    $js\n}"))
  end
  
  for (f, field) in (
    (js_before_create, :beforeCreate), (js_created, :created), (js_before_mount, :beforeMount), (js_mounted, :mounted),
    (js_before_update, :beforeUpdate), (js_updated, :updated), (js_activated, :activated), (js_deactivated, :deactivated),
    (js_before_destroy, :beforeDestroy), (js_destroyed, :destroyed), (js_error_captured, :errorCaptured),)

    js = join_f(f(app), "\n\n    "; pre = strip)
    isempty(js) || push!(vue, field => JSONText("function(){\n    $js\n}"))
  end

  methods = js_methods(app)
  s_methods = if isempty(methods)
    js_methods_events()
  else
    join_f(vcat(methods, js_methods_events), delim; pre = strip)
  end
  push!(vue, :methods    => JSONText("{\n$s_methods\n}"))

  vue
end

"""
    function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of value types. Specialize `Stipple.render` to define custom rendering for your types.
"""
function Stipple.render(val::T, fieldname::Union{Symbol,Nothing}) where {T}
  Stipple.render(val)
end

function Stipple.render(val::T) where {T}
  val
end

"""
    function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of `Reactive` values. Specialize `Stipple.render` to define custom rendering for your type `T`.
"""
function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end