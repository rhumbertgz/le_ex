defmodule BLE.NetUtil do
  @moduledoc """
  This module provides network utilities functions for the leader election
  process
  """

  ############## Public API functions ##############

  @doc """
  This function set a timer that periodically checks the current network status
  of the node.
  """
  def enable_net_checker do
    timer = Application.get_env(:le_ex, :net_timer, 3000)
    Process.send_after(self(), :net_checker , timer)
  end

  @doc """
  This function determines if the network status of the node changed, and returns
  a tuple {TrueOrFalse, oldStatus}.
  """
  def status_changed?(oldStatus, currentStatus) when oldStatus != currentStatus do
    {true, oldStatus}
  end

  def status_changed?(oldStatus, _currentStatus) do
    {false, oldStatus}
  end

  @doc """
  This function returns an atom (:online or :offline) that represents the current
  network status of the node.
  """
  def get_node_status do
    case :inet.getif() do
      {:ok, [_if |[]]} -> :offline
      {:ok, _ifList}   -> :online
    end
  end

  @doc """
  This function returns the current leader in the same cluster of elixir nodes.
  If the cluster only has the current node 'nil' is returned, in other case a tuple
  with the node identifier (number) and node reference is returned.
  """
  def discover_leader() do
    nodes = discover_nodes()
    case get_leader_node(nodes) do
      nil     -> {nil, nil}
      currentLeader -> currentLeader
    end
  end

  @doc """
  This function returns 'true' if the current leader has an ID number greater than
  the current node, or 'false' in other case.
  """
  def follow_leader?(nil) do
    false
  end
  def follow_leader?(leaderId) do
    nodeId = node_id()
    cond do
      leaderId > nodeId -> true
      true              -> false
    end
  end

  @doc """
  This function starts/stops the monitoring of the current leader of the cluster. If
  the current leader leaves the cluster a '{:nodedown, node}' message is received
  by the gen_node module, and then a discover leader process will start.
  """
  def monitor_leader(nil, _flag) do
    true
  end
  def monitor_leader(leader, _flag) when leader == self()  do
    true
  end
  def monitor_leader(leader, flag) do
    Node.monitor(leader,flag)
  end

  @doc """
  This function sends a {:announce_election, nodeId} message to the cluster of
  nodes. If all the 'online' nodes in the cluster have an ID number lesser than
  the proposed leader (current node), then a new  {:announce_leader, currentNode}
  message is sent to cluster. In other case, the current node will wait for a new
  'announce_election' message for a period of time stablished (timeout). After
  that time, if any 'announce_election' is received, the current node will starts
  the election process again.
  """
  def announce_election(timeout \\ 5000) do
    IO.puts "Starting leader election ..."
    msg = {:announce_election, node_id()}
    {replies,_} = :gen_server.multi_call(Node.list(), :bully_node, msg, timeout)
    case unanimous_response?(replies) do
      true   -> announce_as_leader()
                {:leader , Node.self()}
      _other -> check_leader_after(5000)
                {:worker , nil}
    end
  end

  @doc """
  This function sends a {:announce_leader, currentNode} message to the cluster
  announcing that the current node is the new leader.
  """
  def announce_as_leader do
      req = {:announce_leader, Node.self()}
      BLE.GenNode.abcast(:bully_node, req)
  end

  @doc """
  This function returns a list of current nodes in the cluster.
  """
  def discover_nodes do
    Application.ensure_all_started(:nodefinder)
    discover_process(:online)
    IO.puts "Searching nodes ..."
    Process.sleep(2000)
    listNodes = Node.list()
    IO.puts "Nodes founded:"
    IO.inspect listNodes
    listNodes
  end

  @doc """
  This function enables the discover process of current nodes in the cluster.
  """
  def discover_process(:online)  do
    :nodefinder.multicast_start()
  end

  @doc """
  This function disables the discover process of current nodes in the cluster.
  """
  def discover_process(:offline)  do
    :nodefinder.multicast_stop()
  end

  @doc """
  This function send a message to the current node to check the leader after the
  time (milliseconds) specified.
  """
  def check_leader_after(ms_time) do
    Process.send_after(self(), :check_leader, ms_time)
  end

  @doc """
  This function returns the ID number of a NodeRef value.
  """
  def node_id(node \\ Node.self()) do
    node
    |> Atom.to_string()
    |> String.split("@")
    |> List.first()
    |> String.to_integer
  end

def create_node_name do
  {:ok, [{ {n1, n2, n3, n4}, _ ,_} | _rest]} = :inet.getif()
  :"#{n4}@#{n1}.#{n2}.#{n3}.#{n4}"
end



  ############## Utilities functions ##############
  defp get_leader_node([]) do
    nil
  end

  defp get_leader_node([node| rest]) do
    current_leader(rest, {node_id(node), node})
  end

  defp current_leader([], currentLeader) do
    currentLeader
  end

  defp current_leader([node| rest], {leaderId, _} = currentLeader ) do
    nodeId = node_id(node)
    cond do
      (nodeId > leaderId) -> current_leader(rest, {nodeId, node})
                     true -> current_leader(rest, currentLeader)
    end
  end

  defp unanimous_response?([]) do
    true
  end

  defp unanimous_response?(replies) do
    Enum.all?(replies, fn({_node, reply}) -> reply == :yes end)
  end
end
