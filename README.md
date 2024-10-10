# `core`

Welcome to the `core` package. Simulo adds this package to your `packages` and replaces it every time you change Simulo versions (we check the `last_version` file), or when the `packages` directory is created.

All of the built-in Simulo tools are defined here, with the current exception of the **Drag Tool**. Soon enough, the drag tool will also be made in Lua and defined in `core`.

You can prevent Simulo from adding/replacing `core` by setting `replace_core` to `false` in your `config.toml`.

## Strange Tool Names?

Currently, Simulo has no way to customize the order of tools, they are instead sorted alphabetically by name. For this reason, we name tools like `circle` "Round Thing" so they show up where we would like them to.

Later on, this will change when Simulo can have a custom tool order.