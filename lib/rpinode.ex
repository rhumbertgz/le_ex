defmodule RPiNode do
  use BLE.GenNode
  alias BLE.GenNode

  def start_node() do
    GenNode.start(__MODULE__)
  end

  def start_node(name) do
    GenNode.start(name, :cluster, __MODULE__)
  end

  def stop_node(node) do
    GenNode.stop(node)
  end

  def on_status_change(:online, nodeState) do
    IO.inspect "on_status_change -> online"
      # code here
    {:ok, nodeState}
  end

  def on_status_change(:offline, nodeState) do
    IO.inspect "on_status_change -> offline"
    # code here
    {:ok, nodeState}
  end

  def on_role_change(:worker, nodeState) do
    IO.inspect "on_role_change -> worker"
    # code here
    {:ok, nodeState}
  end

  def on_role_change(:leader, nodeState) do
    IO.inspect "on_role_change -> leader"
    # code here
    {:ok, nodeState}
  end

  def on_leader_election(leader, nodeState) do
    IO.inspect "on_leader_election -> #{leader}"
    # code here
    {:ok, nodeState}
  end

end
