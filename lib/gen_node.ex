defmodule BLE.GenNode do
  import BLE.NetUtil
  alias BLE.Metadata

  @callback init(args :: term) ::
    {:ok, nodeState} |
    {:ok, nodeState, timeout | :hibernate} |
    :ignore |
    {:stop, reason :: any} when nodeState: node_state

  @callback handle_call(request :: term, from, nodeState :: node_state) ::
    {:reply, reply, new_nstate} |
    {:reply, reply, new_nstate, timeout | :hibernate} |
    {:noreply, new_nstate} |
    {:noreply, new_nstate, timeout | :hibernate} |
    {:stop, reason, reply, new_nstate} |
    {:stop, reason, new_nstate} when reply: term, new_nstate: node_state, reason: term

  @callback handle_cast(request :: term, nodeState :: node_state) ::
    {:noreply, new_nstate} |
    {:noreply, new_nstate, timeout | :hibernate} |
    {:stop, reason :: term, new_nstate} when new_nstate: node_state

  @callback handle_info(msg :: :timeout | term, nodeState :: node_state) ::
    {:noreply, new_nstate} |
    {:noreply, new_nstate, timeout | :hibernate} |
    {:stop, reason :: term, new_nstate} when new_nstate: node_state

  @callback terminate(reason, nodeState :: node_state) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term

  @callback code_change(old_vsn, nodeState :: node_state, extra :: term) ::
    {:ok, new_nstate :: node_state} |
    {:error, reason :: term} when old_vsn: term | {:down, term}

  @callback format_status(reason, pdict_and_nodeState :: list) ::
    term when reason: :normal | :terminate

  @optional_callbacks format_status: 2

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @typedoc "The GenNode metadata"
  @type metadata :: %Metadata{}

  @typedoc "The GenNode state"
  @type node_state :: {state :: term, metadata :: metadata}

  @typedoc "The GenNode name"
  @type name :: atom


  @typedoc """
  Tuple describing the client of a call request.

  `pid` is the pid of the caller and `tag` is a unique term used to identify the
  call.
  """
  @type from :: {pid, tag :: term}

  # Node callbacks for leader election notifications
  @callback on_status_change(status :: atom, nodeState :: node_state):: {:noreply, new_nstate :: node_state}

  @callback on_role_change(role :: atom, nodeState :: node_state):: {:noreply, new_nstate :: node_state}

  @callback on_leader_election(leader :: term, nodeState :: node_state):: {:noreply, new_nstate :: node_state}


  @doc false
  defmacro __using__(_) do
  quote location: :keep do
      @behaviour BLE.GenNode
      import BLE.NetUtil
      alias BLE.Metadata

      @doc false
      def init(args) do
        role = :worker
        status = get_node_status() # :online or :offline
        tRef = enable_net_checker() # periodically checks the network status
        {leaderId, leaderRef} = discover_leader()

        {role, leader} =
          case follow_leader?(leaderId) do
            true   -> monitor_leader(leaderRef, true)
                      {:worker, leaderRef}
            _false -> announce_election()
          end

        # store node metadata for internal automatic tasks
        meta = %Metadata{role: role, status: status,
                       leader: leader, timerRef: tRef}

        nodeState = {args, meta}

        # fire callbacks implementations
        {:ok, nodeState} = on_status_change(status, nodeState)
        {:ok, nodeState} = on_role_change(role, nodeState)

        # returns initial node state
        {:ok, nodeState}
      end

      @doc false
      def handle_info(:net_checker,  {state, %Metadata{ role: role, leader: leader, status: status} = meta}= nodeState) do
        currentStatus = get_node_status()
        statusChanged = status_changed?(status, currentStatus)

        {:ok, {state, meta}} =
          case statusChanged do
              {true, :online} when
               role == :leader -> discover_process(currentStatus)
                                  ns = {state, %{meta | role: :worker, leader: nil, status: currentStatus}}
                                  {:ok, ns} = on_status_change(currentStatus, ns)
                                  on_role_change(:worker, ns)
              {true, :online}  -> discover_process(currentStatus)
                                  ns = {state, %{meta | leader: nil, status: currentStatus}}
                                  on_status_change(currentStatus, ns)
              {true, :offline} -> discover_process(currentStatus)
                                  ns = {state, %{meta | status: currentStatus}}
                                  {:ok, nodeState} = on_status_change(currentStatus, ns)
                                  check_leader_after(1500)
                                  {:ok, nodeState}
                    _othercase -> {:ok, nodeState}
            end

        tRef = enable_net_checker()
        {:noreply, {state, %{meta | timerRef: tRef}} }
      end

     @doc false
     def handle_info({:nodedown, node}, {state, %Metadata{} = meta}) do
       {role, leader} = announce_election()
       meta = %{meta | role: role, leader: leader}
       {:noreply, {state, meta}}
     end

     @doc false
     def handle_info(:check_leader, {state, %Metadata{leader: nil, role: currentRole} = meta} = nodeState) do
       {leaderId, leaderRef} = discover_leader()
       {role, leader} =
         case follow_leader?(leaderId) do
           true   -> monitor_leader(leaderRef, true)
                     {:worker, leaderRef}
           _false -> announce_election()
         end

       meta = %{meta | role: role, leader: leader}
       nodeState = {state, meta}

       {:ok, nodeState} =
         case currentRole != role do
           true  -> on_role_change(role, nodeState)
           false -> {:ok, nodeState}
         end

       {:noreply, nodeState}
     end

      @doc false
      def handle_info(_msg, nodeState), do:  {:noreply, nodeState}

      @doc false
      def on_status_change(_msg, nodeState), do:  {:ok, nodeState}

      @doc false
      def on_role_change(_msg, nodeState), do:  {:ok, nodeState}

      @doc false
      def on_leader_election(_msg, nodeState), do:  {:ok, nodeState}

      @doc false
      def handle_call(:get_leader, _from, {_state, %Metadata{leader: leader}}= nodeState) do
        {:reply, leader, nodeState}
      end


      @doc false
      def handle_call({:announce_election, leaderId}, _from, {state, %Metadata{leader: leader} = meta}) do
        monitor_leader(leader, false)
        {reply, meta} =
          case  follow_leader?(leaderId) do
            true  -> {:yes, meta}
            false -> check_leader_after(1500)
                     {:no, %{meta |leader: nil}}
          end
        {:reply, reply, {state, meta}}
      end

      @doc false
      def handle_call(msg, _from, nodeState) do
        # We do this to trick Dialyzer to not complain about non-local returns.
        reason = {:bad_call, msg}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, nodeState}
        end
      end

      @doc false
      def handle_cast({:announce_leader, leaderRef},{state, %Metadata{role: currentRole} = meta}) do
        {role, meta} =
          case  follow_leader?(node_id(leaderRef)) do
            true  -> monitor_leader(leaderRef, true)
                    {:worker, %{meta |leader: leaderRef, role: :worker}}
            false -> check_leader_after(1500)
                    {:worker, %{meta |leader: nil, role: :worker}}
          end

        nodeState = {state, meta}
        {:ok, nodeState } = on_leader_election(leaderRef, nodeState)

        {:ok, nodeState} =
          case currentRole != role do
            true  -> on_role_change(role, nodeState)
            false -> {:ok, nodeState}
          end

        {:noreply, nodeState}
      end

      @doc false
      def handle_cast(msg, nodeState) do
        # We do this to trick Dialyzer to not complain about non-local returns.
        reason = {:bad_cast, msg}
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> {:stop, reason, nodeState}
        end
      end

      @doc false
      def terminate(_reason, {_state, %Metadata{leader: leader}}) do
        # clean-up
        monitor_leader(leader, false)
        discover_process(:offline)
        :ok
      end
      @doc false
      def code_change(_old, nodeState, _extra), do:  {:ok, nodeState}

      defoverridable [on_status_change: 2, on_role_change: 2, on_leader_election: 2]
    end
  end


  def start(module, args \\ []) do
    start(BLE.NetUtil.create_node_name(), :cluster, module, args)
  end

  @spec start(name :: atom, cookie :: atom, module :: term, args :: term) :: on_start
  def start(name, cookie, module, args \\ []) do
    Node.start(name)
    Node.set_cookie(cookie)
    GenServer.start_link(module, args, name: :bully_node)
  end

  @spec stop(node, reason :: term, timeout) :: :ok
  def stop(node, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(node, reason, timeout)
    Node.stop()
  end

  def get_leader(node, timeout \\ 5000) do
    GenServer.call(node, :get_leader, timeout)
  end

  @doc false
  @spec call(node, term, timeout) :: term
  def call(node, request, timeout \\ 5000) do
    GenServer.call(node, request, timeout)
  end

  @doc false
  @spec cast(node, term) :: :ok
  def cast(node, request) do
    GenServer.cast(node, request)
  end

  @doc false
  @spec abcast([node], name :: atom, term) :: :abcast
  def abcast(nodes \\ Node.list(), name, request) when is_list(nodes) and is_atom(name) do
    GenServer.abcast(nodes, name, request)
  end
end
