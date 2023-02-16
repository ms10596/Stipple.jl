module ReactiveTools

using Stipple
using MacroTools
using MacroTools: postwalk
using OrderedCollections
import Genie
import Stipple: deletemode!, parse_expression!, init_storage

# definition of variables
export @readonly, @private, @in, @out, @jsfn, @readonly!, @private!, @in!, @out!, @jsfn!, @mixin

#definition of handlers/events
export @onchange, @onbutton, @event, @notify

# deletion
export @clear, @clear_vars, @clear_handlers

# app handling
export @page, @init, @handlers, @app, @appname

# js functions on the front-end (see Vue.js docs)
export @methods, @watch, @computed, @created, @mounted, @client_data, @add_client_data

export DEFAULT_LAYOUT, Page

export @onchangeany # deprecated

const REACTIVE_STORAGE = LittleDict{Module,LittleDict{Symbol,Expr}}()
const HANDLERS = LittleDict{Module,Vector{Expr}}()
const TYPES = LittleDict{Module,Union{<:DataType,Nothing}}()

function DEFAULT_LAYOUT(; title::String = "Genie App")
  """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <% Stipple.sesstoken() %>
    <title>$title</title>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "genieapp.css")) %>
    <link rel='stylesheet' href='/css/genieapp.css'>
    <% else %>
    <% end %>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "autogenerated.css")) %>
    <link rel='stylesheet' href='/css/autogenerated.css'>
    <% else %>
    <% end %>
    <style>
      ._genie_logo {
        background:url('$(Genie.Assets.asset_path(Stipple.assets_config, :img, file="genie-logo"))') no-repeat;background-size:40px;
        padding-top:22px;padding-right:10px;color:transparent;font-size:9pt;
      }
      ._genie .row .col-12 { width:50%;margin:auto; }
    </style>
  </head>
  <body>
    <div class='container'>
      <div class='row'>
        <div class='col-12'>
          <% page(model, partial = true, v__cloak = true, [@yield], @iif(:isready)) %>
        </div>
      </div>
    </div>
    <% if isfile(joinpath(Genie.config.server_document_root, "js", "genieapp.js")) %>
    <script src='/js/genieapp.js'></script>
    <% else %>
    <% end %>
    <footer class='_genie container'>
      <div class='row'>
        <div class='col-12'>
          <p class='text-muted credit' style='text-align:center;color:#8d99ae;'>Built with
            <a href='https://genieframework.com' target='_blank' class='_genie_logo' ref='nofollow'>Genie</a>
          </p>
        </div>
      </div>
    </footer>
  </body>
</html>
"""
end

function model_typename(m::Module)
  isdefined(m, :__typename__) ? m.__typename__[] : "$(m)_ReactiveModel"
end

macro appname(expr)
  expr isa Symbol || (expr = Symbol(@eval(__module__, $expr)))
  clear_type(__module__)
  ex = quote end
  if isdefined(__module__, expr)
    push!(ex.args, :(Stipple.ReactiveTools.delete_handlers_fn($__module__)))
    push!(ex.args, :(Stipple.ReactiveTools.delete_events($expr)))
  end
  if isdefined(__module__, :__typename__) && __module__.__typename__ isa Ref{String}
    push!(ex.args, :(__typename__[] = $(string(expr))))
  else
    push!(ex.args, :(const __typename__ = Ref{String}($(string(expr)))))
    push!(ex.args, :(__typename__[]))
  end
  :($ex) |> esc
end

macro appname()
  # reset appname to default
  appname = "$(__module__)_ReactiveModel"
  :(isdefined($__module__, :__typename__) ? @appname($appname) : $appname) |> esc
end

function Stipple.init_storage(m::Module)
  (m == @__MODULE__) && return nothing
  haskey(REACTIVE_STORAGE, m) || (REACTIVE_STORAGE[m] = Stipple.init_storage())
  haskey(TYPES, m) || (TYPES[m] = nothing)
  REACTIVE_STORAGE[m]
end

function Stipple.setmode!(expr::Expr, mode::Int, fieldnames::Symbol...)
  fieldname in [Stipple.CHANNELFIELDNAME, :modes__] && return

  d = eval(expr.args[2])
  for fieldname in fieldnames
    mode == PUBLIC ? delete!(d, fieldname) : d[fieldname] = mode
  end
  expr.args[2] = QuoteNode(d)
end

#===#

function clear_type(m::Module)
  TYPES[m] = nothing
end

function delete_bindings!(m::Module)
  clear_type(m)
  delete!(REACTIVE_STORAGE, m)
  nothing
end

function bindings(m)
  init_storage(m)
  REACTIVE_STORAGE[m]
end

function delete_handlers_fn(m::Module)
  if isdefined(m, :__GF_AUTO_HANDLERS__)
    Base.delete_method.(methods(m.__GF_AUTO_HANDLERS__))
  end
end

function delete_events(m::Module)
  haskey(TYPES, m) && TYPES[m] isa DataType && delete_events(TYPES[m])
end

function delete_events(::Type{M}) where M
  # delete event functions
  mm = methods(Base.notify)
  for m in mm
    hasproperty(m.sig, :parameters) || continue
    T =  m.sig.parameters[2]
    if T <: M || T == Type{M} || T == Type{<:M}
      Base.delete_method(m)
    end
  end
  nothing
 end

function delete_handlers!(m::Module)
  delete!(HANDLERS, m)
  delete_handlers_fn(m)
  delete_events(m)
  nothing
end

#===#

macro clear()
  delete_bindings!(__module__)
  delete_handlers!(__module__)
end

macro clear(args...)
  haskey(REACTIVE_STORAGE, __module__) || return
  for arg in args
    arg in [Stipple.CHANNELFIELDNAME, :modes__] && continue
    delete!(REACTIVE_STORAGE[__module__], arg)
  end
  deletemode!(REACTIVE_STORAGE[__module__][:modes__], args...)

  update_storage(__module__)

  REACTIVE_STORAGE[__module__]
end

macro clear_vars()
  delete_bindings!(__module__)
end

macro clear_handlers()
  delete_handlers!(__module__)
end

import Stipple.@type
macro type()
  Stipple.init_storage(__module__)
  type = if TYPES[__module__] !== nothing
    TYPES[__module__]
  else
    modelname = Symbol(model_typename(__module__))
    storage = REACTIVE_STORAGE[__module__]
    TYPES[__module__] = @eval(__module__, Stipple.@type($modelname, $storage))
  end

  esc(:($type))
end

function update_storage(m::Module)
  clear_type(m)
  # isempty(Stipple.Pages._pages) && return
  # instance = @eval m Stipple.@type()
  # for p in Stipple.Pages._pages
  #   p.context == m && (p.model = instance)
  # end
end

import Stipple: @vars, @add_vars

macro vars(expr)
  init_storage(__module__)

  REACTIVE_STORAGE[__module__] = @eval(__module__, Stipple.@var_storage($expr))

  update_storage(__module__)
  REACTIVE_STORAGE[__module__]
end

macro add_vars(expr)
  init_storage(__module__)
  REACTIVE_STORAGE[__module__] = Stipple.merge_storage(REACTIVE_STORAGE[__module__], @eval(__module__, Stipple.@var_storage($expr)))

  update_storage(__module__)
end

macro model()
  esc(quote
    ReactiveTools.@type() |> Base.invokelatest
  end)
end

macro app(expr)
  delete_bindings!(__module__)
  delete_handlers!(__module__)

  init_handlers(__module__)
  init_storage(__module__)

  quote
    $expr
    
    @handlers
  end |> esc
end

#===#

function binding(expr::Symbol, m::Module, @nospecialize(mode::Any = nothing); source = nothing, reactive = true)
  binding(:($expr = $expr), m, mode; source, reactive)
end

function binding(expr::Expr, m::Module, @nospecialize(mode::Any = nothing); source = nothing, reactive = true)
  (m == @__MODULE__) && return nothing

  intmode = @eval Stipple $mode
  init_storage(m)

  var, field_expr = parse_expression!(expr, reactive ? mode : nothing, source, m)
  REACTIVE_STORAGE[m][var] = field_expr

  reactive || setmode!(REACTIVE_STORAGE[m][:modes__], intmode, var)
  reactive && setmode!(REACTIVE_STORAGE[m][:modes__], PUBLIC, var)

  # remove cached type and instance, update pages
  update_storage(m)
end

function binding(expr::Expr, storage::LittleDict{Symbol, Expr}, @nospecialize(mode::Any = nothing); source = nothing, reactive = true, m::Module)
  intmode = @eval Stipple $mode

  var, field_expr = parse_expression!(expr, reactive ? mode : nothing, source, m)
  storage[var] = field_expr

  reactive || setmode!(storage[:modes__], intmode, var)
  reactive && setmode!(storage[:modes__], PUBLIC, var)

  storage
end

# this macro needs to run in a macro where `expr`is already defined
macro report_val()
  quote
    val = expr isa Symbol ? expr : expr.args[2]
    issymbol = val isa Symbol
    :(if $issymbol
      if isdefined(@__MODULE__, $(QuoteNode(val)))
        $val
      else
        @info(string("Warning: Variable '", $(QuoteNode(val)), "' not yet defined"))
      end
    else
      Stipple.Observables.to_value($val)
    end) |> esc
  end |> esc
end

# this macro needs to run in a macro where `expr`is already defined
macro define_var()
  quote
    ( expr isa Symbol || expr.head !== :(=) ) && return expr
    var = expr.args[1] isa Symbol ? expr.args[1] : expr.args[1].args[1]
    new_expr = :($var = Stipple.Observables.to_value($(expr.args[2])))
    esc(:($new_expr))
  end |> esc
end

# works with
# @in a = 2
# @in a::Vector = [1, 2, 3]
# @in a::Vector{Int} = [1, 2, 3]

for (fn, mode) in [(:in, :PUBLIC), (:out, :READONLY), (:jsnfn, :JSFUNCTION), (:private, :PRIVATE)]
  fn! = Symbol(fn, "!")
  Core.eval(@__MODULE__, quote

    macro $fn!(expr)
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__)
      esc(:($expr))
    end

    macro $fn!(flag, expr)
      flag != :non_reactive && return esc(:(ReactiveTools.$fn!($flag, _, $expr)))
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__, reactive = false)
      esc(:($expr))
    end

    macro $fn(location, flag, expr)
      reactive = flag != :non_reactive
      ex = [expr isa Symbol ? expr : copy(expr)]
      loc = location isa Symbol ? QuoteNode(location) : location

      quote
        local location = isdefined($__module__, $loc) ? eval($loc) : $loc
        local storage = location isa DataType ? Stipple.model_to_storage(location) : location isa LittleDict ? location : Stipple.init_storage()

        Stipple.ReactiveTools.binding($ex[1], storage, $$mode; source = $__source__, reactive = $reactive, m = $__module__)
        location isa DataType || location isa Symbol ? eval(:(@type($$loc, $storage))) : location
      end |> esc
    end

    macro $fn(expr)
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__)
      @report_val()
    end

    macro $fn(flag, expr)
      flag != :non_reactive && return esc(:(ReactiveTools.@fn($flag, _, $expr)))
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__, reactive = false)
      @report_val()
    end
  end)
end

macro mixin(expr, prefix = "", postfix = "")
  # if prefix is not a String then call the @mixin version for generic model types
  prefix isa String || return quote
    @mixin $expr $prefix $postfix "" 
  end

  storage = init_storage(__module__)

  quote
    Stipple.ReactiveTools.update_storage($__module__)
    Stipple.ReactiveTools.@mixin $storage $expr $prefix $postfix
  end
end

macro mixin(location, expr, prefix, postfix)
  if hasproperty(expr, :head) && expr.head == :(::)
    prefix = string(expr.args[1])
    expr = expr.args[2]
  end
  loc = location isa Symbol ? QuoteNode(location) : location
  
  x = Core.eval(__module__, expr)
  quote
    local location = $loc isa Symbol && isdefined($__module__, $loc) ? $__module__.$(loc isa QuoteNode ? loc.value : loc) : $loc
    local storage = location isa DataType ? Stipple.model_to_storage(location) : location isa LittleDict ? location : Stipple.init_storage()
    M = $x isa DataType ? $x : typeof($x) # really needed?
    local mixin_storage = Stipple.model_to_storage(M, $(QuoteNode(prefix)), $postfix)
    
    merge!(storage, Stipple.merge_storage(storage, mixin_storage))
    location isa DataType || location isa Symbol ? eval(:(@type($$loc, $storage))) : location
    mixin_storage
  end |> esc
end

#===#

function init_handlers(m::Module)
  get!(Vector{Expr}, HANDLERS, m)
end

macro init(modeltype)
  quote
    local new_handlers = false
    local initfn =  if isdefined($__module__, :init_from_storage)
                      $__module__.init_from_storage
                    else
                      $__module__.init
                    end
    local handlersfn =  if isdefined($__module__, :__GF_AUTO_HANDLERS__)
                          if length(methods($__module__.__GF_AUTO_HANDLERS__)) == 0
                            @eval(@handlers())
                            new_handlers = true
                          end
                          $__module__.__GF_AUTO_HANDLERS__
                        else
                          identity
                        end

    instance = new_handlers ? Base.invokelatest(handlersfn, $modeltype |> initfn) : $modeltype |> initfn |> handlersfn
    for p in Stipple.Pages._pages
      p.context == $__module__ && (p.model = instance)
    end
    instance
  end |> esc
end

macro init()
  quote
    let type = Stipple.@type
      @init(type)
    end
  end |> esc
end

macro handlers()
  handlers = init_handlers(__module__)

  quote
    function __GF_AUTO_HANDLERS__(__model__)
      $(handlers...)

      return __model__
    end
  end |> esc
end

macro handlers(expr)
  delete_handlers!(__module__)
  init_handlers(__module__)

  quote
    $expr

    @handlers
  end |> esc
end

macro app(typename, expr, handlers_fn_name = :handlers)
  storage = init_storage()
  quote
    Stipple.@type $typename $storage

    Stipple.ReactiveTools.@handlers $typename $expr $handlers_fn_name
  end |> esc
end

macro handlers(typename, expr, handlers_fn_name = :handlers)
  expr = wrap(expr, :block)
  i_start = 1
  handlercode = []
  initcode = quote end
  storage = isdefined(__module__, typename) ? @eval(__module__, Stipple.model_to_storage($typename)) : Stipple.init_storage()

  for (i, ex) in enumerate(expr.args)
    if ex isa Expr
      if ex.head == :macrocall && ex.args[1] in Symbol.(["@onbutton", "@onchange"])
        ex_index = isa.(ex.args, Union{Symbol, Expr})
        if sum(ex_index) < 4
          pos = findall(ex_index)[2]
          insert!(ex.args, pos, typename)
        end
        push!(handlercode, expr.args[i_start:i]...)
      else
        if ex.head == :macrocall && ex.args[1] in Symbol.(["@in", "@out", "@private", "@readonly", "@jsfn", "@mixin"])
          ex_index = isa.(ex.args, Union{Symbol, Expr})
          pos = findall(ex_index)[2]
          sum(ex_index) == 2 && ex.args[1] != Symbol("@mixin") && insert!(ex.args, pos, :_)
          insert!(ex.args, pos, :__storage__)
        end
        push!(initcode.args, expr.args[i_start:i]...)
      end
      i_start = i + 1
    end
  end

  initcode = quote
    __storage__ = $storage
    $(initcode.args...)
    __storage__
  end

  handlercode_final = []
  for ex in handlercode
    if ex isa Expr
      push!(handlercode_final, @eval(__module__, $ex).args...)
    else
      push!(handlercode_final, ex)
    end
  end

  quote
    $initcode
    @eval Stipple.@type($typename, __storage__)

    Stipple.ReactiveTools.delete_events($typename)

    function $handlers_fn_name(__model__)
      $(handlercode_final...)

      __model__
    end
    ($typename, $handlers_fn_name)
  end |> esc
end

function wrap(expr, wrapper = nothing)
  if wrapper !== nothing && (! isa(expr, Expr) || expr.head != wrapper)
    Expr(wrapper, expr)
  else
    expr
  end
end

function transform(expr, vars::Vector{Symbol}, test_fn::Function, replace_fn::Function)
  replaced_vars = Symbol[]
  ex = postwalk(expr) do x
      if x isa Expr
          if x.head == :call
            f = x
            while f.args[1] isa Expr && f.args[1].head == :ref
              f = f.args[1]
            end
            if f.args[1] isa Symbol && test_fn(f.args[1])
              union!(push!(replaced_vars, f.args[1]))
              f.args[1] = replace_fn(f.args[1])
            end
            if x.args[1] == :notify && length(x.args) == 2
              if @capture(x.args[2], __model__.fieldname_[])
                x.args[2] = :(__model__.$fieldname)
              elseif x.args[2] isa Symbol
                x.args[2] = :(__model__.$(x.args[2]))
              end
            end
          elseif x.head == :kw && test_fn(x.args[1])
            x.args[1] = replace_fn(x.args[1])
          elseif x.head == :parameters
            for (i, a) in enumerate(x.args)
              if a isa Symbol && test_fn(a)
                new_a = replace_fn(a)
                x.args[i] = new_a in vars ? :($(Expr(:kw, new_a, :(__model__.$new_a[])))) : new_a
              end
            end
          elseif x.head == :ref && length(x.args) == 2 && x.args[2] == :!
            @capture(x.args[1], __model__.fieldname_[]) && (x.args[1] = :(__model__.$fieldname))
          elseif x.head == :macrocall && x.args[1] == Symbol("@push")
            x = :(push!(__model__))
          end
      end
      x
  end
  ex, replaced_vars
end

mask(expr, vars::Vector{Symbol}) = transform(expr, vars, in(vars), x -> Symbol("_mask_$x"))
unmask(expr, vars = Symbol[]) = transform(expr, vars, x -> startswith(string(x), "_mask_"), x -> Symbol(string(x)[7:end]))[1]

function fieldnames_to_fields(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x) : x
  end
end

function fieldnames_to_fields(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x)
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y) : y
        end
      end
    end
    x
  end
end

function fieldnames_to_fieldcontent(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x[]) : x
  end
end

function fieldnames_to_fieldcontent(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x[])
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y[]) : y
        end
      end
    end
    x
  end
end

function get_known_vars(M::Module)
  init_storage(M)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in REACTIVE_STORAGE[M]
    k in [:channel__, :modes__] && continue
    is_reactive = startswith(string(Stipple.split_expr(v)[2]), r"(Stipple\.)?R(eactive)?($|{)")
    push!(is_reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

function get_known_vars(::Type{M}) where M<:ReactiveModel
  CM = Stipple.get_concrete_type(M)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in zip(fieldnames(CM), fieldtypes(CM))
    k in [:channel__, :modes__] && continue
    push!(v <: Reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

macro onchange(var, expr)
  quote
    @onchange $__module__ $var $expr
  end |> esc
end

macro onchange(location, vars, expr)
  loc::Union{Module, Type{<:M}} where M<:ReactiveModel = @eval __module__ $location
  vars = wrap(vars, :tuple)
  expr = wrap(expr, :block)

  loc isa Module && init_handlers(loc)
  known_reactive_vars , known_non_reactive_vars= get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  on_vars = fieldnames_to_fields(vars, known_vars)

  expr, used_vars = mask(expr, known_vars)
  do_vars = Symbol[]

  for a in vars.args
    push!(do_vars, a isa Symbol && ! in(a, used_vars) ? a : :_)
  end

  replace_vars = setdiff(known_vars, do_vars)
  expr = fieldnames_to_fields(expr, known_non_reactive_vars, replace_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars, replace_vars)
  expr = unmask(expr, replace_vars)

  fn = length(vars.args) == 1 ? :on : :onany
  ex = quote
    $fn($(on_vars.args...)) do $(do_vars...)
        $(expr.args...)
    end
  end

  loc isa Module && push!(HANDLERS[__module__], ex)
  output = [ex]
  quote
    function __GF_AUTO_HANDLERS__ end
    Base.delete_method.(methods(__GF_AUTO_HANDLERS__))
    $output[end]
  end |> esc
end

macro onchangeany(var, expr)
  quote
    @warn("The macro `@onchangeany` is deprecated and should be replaced by `@onchange`")
    @onchange $vars $expr
  end |> esc
end

macro onbutton(var, expr)
  quote
    @onbutton $__module__ $var $expr
  end |> esc
end

macro onbutton(location, var, expr)
  loc::Union{Module, Type{<:M}} where M<:ReactiveModel = @eval __module__ $location
  expr = wrap(expr, :block)
  loc isa Module && init_handlers(loc)

  known_reactive_vars , known_non_reactive_vars= get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  var = fieldnames_to_fields(var, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, known_vars)
  
  ex = :(onbutton($var) do
    $(expr.args...)
  end)
  loc isa Module && push!(HANDLERS[__module__], ex)
  output = [ex]
  
  quote
    function __GF_AUTO_HANDLERS__ end
    Base.delete_method.(methods(__GF_AUTO_HANDLERS__))
    $output[end]
  end |> esc
end

#===#

macro page(url, view, layout, model, context)
  quote
    Stipple.Pages.Page( $url;
                        view = $view,
                        layout = $layout,
                        model = $model,
                        context = $context)
  end |> esc
end

macro page(url, view, layout, model)
  :(@page($url, $view, $layout, $model, $__module__)) |> esc
end

macro page(url, view, layout)
  :(@page($url, $view, $layout, () -> @eval($__module__, @init()))) |> esc
end

macro page(url, view)
  :(@page($url, $view, Stipple.ReactiveTools.DEFAULT_LAYOUT())) |> esc
end

macro methods(expr)
  esc(quote
    let M = Stipple.@type
      Stipple.js_methods(::M) = $expr
    end
  end)
end

macro methods(T, expr)
  esc(:(Stipple.js_methods(::$T) = $expr))
end

macro watch(expr)
  esc(quote
    let M = Stipple.@type
      Stipple.js_watch(::M) = $expr
    end
  end)
end

macro watch(T, expr)
  esc(:(Stipple.js_watch(::$T) = $expr))
end

macro computed(expr)
  esc(quote
    let M = Stipple.@type
      Stipple.js_computed(::M) = $expr
    end
  end)
end

macro computed(T, expr)
  esc(:(Stipple.js_computed(::$T) = $expr))
end

macro created(expr)
  esc(quote
    let M = Stipple.@type
      Stipple.js_created(::M) = $expr
    end
  end)
end

macro created(T, expr)
  esc(:(Stipple.js_created(::$T) = $expr))
end

macro mounted(expr)
  esc(quote
    let M = Stipple.@type
      Stipple.js_mounted(::M) = $expr
    end
  end)
end

macro mounted(T, expr)
  esc(:(Stipple.js_mounted(::$T) = $expr))
end

macro event(M, eventname, expr)
  known_vars = get_known_vars(@eval(__module__, $M))

  expr, used_vars = mask(expr, known_vars)
  expr = unmask(fieldnames_to_fieldcontent(expr, known_vars), known_vars)
  T = eventname isa QuoteNode ? eventname : QuoteNode(eventname)
  
  quote
    function Base.notify(__model__::$M, ::Val{$T}, @nospecialize(event))
        $expr
    end
  end |> esc
end

macro event(event, expr)
  quote
    @event @type() $event $expr
  end |> esc
end

macro client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = @type
      Stipple.client_data(::M) = $output
    end
  end)
end

macro add_client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = @type
      cd_old = Stipple.client_data(M())
      cd_new = $output
      Stipple.client_data(::M) = merge(d1, d2)
    end
  end)
end

macro notify(args...)
  for arg in args
    arg isa Expr && arg.head == :(=) && (arg.head = :kw)
  end

  quote
    Base.notify(__model__, $(args...))
  end |> esc
end

end