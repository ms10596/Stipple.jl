"""
    function js_methods(app::T) where {T<:ReactiveModel}

Defines js functions for the `methods` section of the vue element.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example 1

```julia
js_methods(::MyDashboard) = \"\"\"
  mysquare: function (x) {
    return x^2
  }
  myadd: function (x, y) {
    return x + y
  }
\"\"\"
```
### Example 2
```
js_methods(::MyDashboard) = Dict(:f => "function(x) { console.log('x: ' + x) })
```
### Example 3
```
js_greet() = :greet => "function(name) {console.log('Hello ' + name)}"
js_bye() = :bye => "function() {console.log('Bye!')}"
js_methods(::MyDashboard) = [js_greet, js_bye]
```
"""
function js_methods(app::T)::String where {T<:ReactiveModel}
  ""
end

function js_methods_events()::String
"""
  handle_event: function (event, handler) {
    Genie.WebChannels.sendMessageTo(window.CHANNEL, 'events', {
        'event': {
            'name': handler,
            'event': event
        }
    })
  }
"""
end

"""
    function js_computed(app::T) where {T<:ReactiveModel}

Defines js functions for the `computed` section of the vue element.
These properties are updated every time on of the inner parameters changes its value.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example

```julia
js_computed(app::MyDashboard) = \"\"\"
  fullName: function () {
    return this.firstName + ' ' + this.lastName
  }
\"\"\"
```
"""
function js_computed(app::T)::String where {T<:ReactiveModel}
  ""
end

const jscomputed = js_computed

"""
    function js_watch(app::T) where {T<:ReactiveModel}

Defines js functions for the `watch` section of the vue element.
These functions are called every time the respective property changes.
Expected result types of the function are
  - `String` containing javascript code
  - `Pair` of function name and function code
  - `Function` returning String of javascript code
  - `Dict` of function names and function code
  - `Vector` of the above

### Example

Updates the `fullName` every time `firstName` or `lastName` changes.

```julia
js_watch(app::MyDashboard) = \"\"\"
  firstName: function (val) {
    this.fullName = val + ' ' + this.lastName
  },
  lastName: function (val) {
    this.fullName = this.firstName + ' ' + val
  }
\"\"\"
```
"""
function js_watch(m::T)::String where {T<:ReactiveModel}
  ""
end

const jswatch = js_watch

"""
    function client_data(app::T)::String where {T<:ReactiveModel}

Defines additional data that will only be visible by the browser.

It is meant to keep volatile data, e.g. form data that needs to pass a validation first.
In order to use the data you most probably also want to define [`js_methods`](@ref)
### Example

```julia
import Stipple.client_data
client_data(m::Example) = client_data(client_name = js"null", client_age = js"null", accept = false)
```
will define the additional fields `client_name`, `client_age` and `accept` for the model `Example`. These should, of course, not overlap with existing fields of your model.
"""
client_data(app::T) where T <: ReactiveModel = Dict{String, Any}()

client_data(;kwargs...) = Dict{String, Any}([String(k) => v for (k, v) in kwargs]...)

for (f, field) in (
  (:js_before_create, :beforeCreate), (:js_created, :created), (:js_before_mount, :beforeMount), (:js_mounted, :mounted),
  (:js_before_update, :beforeUpdate), (:js_updated, :updated), (:js_activated, :activated), (:js_deactivated, :deactivated),
  (:js_before_destroy, :beforeDestroy), (:js_destroyed, :destroyed), (:js_error_captured, :errorCaptured),)

  field_str = string(field)
  Core.eval(@__MODULE__, quote
    """
        function $($f)(app::T)::Union{Function, String, Vector} where {T<:ReactiveModel}

    Defines js statements for the `$($field_str)` section of the vue element.

    Result types of the function can be
    - `String` containing javascript code
    - `Function` returning String of javascript code
    - `Vector` of the above

    ### Example 1

    ```julia
    $($f)(app::MyDashboard) = \"\"\"
        if (this.cameraon) { startcamera() }
    \"\"\"
    ```

    ### Example 2

    ```julia
    startcamera() = "if (this.cameraon) { startcamera() }"
    stopcamera() = "if (this.cameraon) { stopcamera() }"

    $($f)(app::MyDashboard) = [startcamera, stopcamera]
    ```
    Checking the result can be done in the following way
    ```
    julia> render(MyApp())[:$($field_str)]
    JSONText("function(){\n    if (this.cameraon) { startcamera() }\n\n    if (this.cameraon) { stopcamera() }\n}")
    ```
    """
    function $f(app::T)::String where {T<:ReactiveModel}
      ""
    end
  end)
end

const jscreated = js_created
const jsmounted = js_mounted