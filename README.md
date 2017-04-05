# Leader Election Lib

## Usage

In the directory of the project, open a terminal and type:

iex -S mix

Once we are in the Interactive Elixir Shell or REPL, we only need to start a new node using the function `GenNode.start`.
In our example we encapsulate `start` function in the function `RPiNode.start_node`.

```elixir
{:ok, n} = RPiNode.start_node :"1@10.26.2.91"
```

To stop a node we should use the function `GenNode.stop`. In the same way that `GenNode.start` we encapsulate `GenNode.stop` function with the function `RPiNode.stop_node` of our example.

```elixir
 RPiNode.stop_node n
 ```

In a single machine we can open several terminals and then starting multiple nodes. All node (in our example a RasberryPI) names should have this pattern  :"RPiNumber@RPi_IP_ADDRESS", where the first part is a unique number and the second part is the IP address of our device.

For example:

```elixir
{:ok, n1} = RPiNode.start_node :"1@10.26.2.91"

{:ok, n2} = RPiNode.start_node :"2@10.26.2.92"

{:ok, n3} = RPiNode.start_node :"3@10.26.2.93"
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `le_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:le_ex, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/le_ex](https://hexdocs.pm/le_ex).
