defmodule Ecto.Adapters.Riak.Worker do
  use GenServer

  alias Ecto.Adapters.Riak

  @timeout 5000

  def start(args) do
    :gen_server.start(__MODULE__, args, [])
  end

  def start_link(args) do
    :gen_server.start_link(__MODULE__, args, [])
  end


  def ping!(worker, timeout \\ @timeout) do
    case :gen_server.call(worker, {:ping, timeout}, timeout) do
      :pong -> :pong
      {:error, err} -> raise %Riak.Error{riak: err}
    end
  end


  def create_search_index!(worker, name, schema, search_admin_opts, timeout \\ @timeout) do
    case :gen_server.call(worker, {:create_search_index, name, schema, search_admin_opts}, timeout) do
      :ok -> :ok
      {:error, err} -> raise %Riak.Error{riak: err}
    end
  end


  def delete_search_index!(worker, name, schema, search_admin_opts, timeout \\ @timeout) do
    case :gen_server.call(worker, {:delete_search_index, name, schema, search_admin_opts}, timeout) do
      :ok -> :ok
      {:error, err} -> raise %Riak.Error{riak: err}
    end
  end


  def insert!(worker, bucket, model, opts, timeout \\ @timeout) do
    case :gen_server.call(worker, {:insert, bucket, model, opts, timeout}, timeout) do
      {:ok, model}  -> model
      {:error, err} -> raise %Riak.Error{riak: err}
    end
  end


  def update!(worker, bucket, model, opts, timeout \\ @timeout) do
    case :gen_server.call(worker, {:update, bucket, model, opts, timeout}, timeout) do
      {:ok, model}  -> model
      {:error, err} -> raise %Riak.Error{riak: err}
    end
  end


  def run_custom!(worker, fun) do
    :gen_server.call(worker, {:run_custom, fun}, @timeout)
  end


  def query!(worker, sql, params, timeout \\ @timeout) do
    case :gen_server.call(worker, {:query, sql, params, timeout}, timeout) do
      {:ok, res} -> res
      {:error, %Riak.Error{} = err} -> raise err
    end
  end


  def monitor_me(worker) do
    :gen_server.cast(worker, {:monitor, self})
  end

  def demonitor_me(worker) do
    :gen_server.cast(worker, {:demonitor, self})
  end

  def init(opts) do
    Process.flag(:trap_exit, true)

    eager? = Keyword.get(opts, :lazy, true) in [false, "false"]

    if eager? do
      case Riak.Connection.start_link(opts) do
        {:ok, conn} ->
          conn = conn
        _ ->
          :ok
      end
    end

    {:ok, Map.merge(new_state, %{conn: conn, params: opts})}
  end

  # Connection is disconnected, reconnect before continuing
  def handle_call(request, from, %{conn: nil, params: params} = s) do
    case Riak.Connection.start_link(params) do
      {:ok, conn} ->
        handle_call(request, from, %{s | conn: conn})
      {:error, err} ->
        {:reply, {:error, err}, s}
    end
  end


  def handle_call({:create_search_index, name, schema, search_admin_opts}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.create_search_index(conn, name, schema, search_admin_opts), s}
  end


  def handle_call({:delete_search_index, name, schema, search_admin_opts}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.delete_search_index(conn, name, schema, search_admin_opts), s}
  end


  def handle_call({:run_custom, fun}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.run_custom(conn, fun), s}
  end


  def handle_call({:ping, timeout}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.ping(conn, timeout), s}
  end


  def handle_call({:insert, bucket, model, opts, timeout}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.insert(conn, bucket, model, opts, timeout), s}
  end


  def handle_call({:update, bucket, model, opts, timeout}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.update(conn, bucket, model, opts, timeout), s}
  end


  def handle_call({:query, sql, params, timeout}, _from, %{conn: conn} = s) do
    {:reply, Riak.Connection.query(conn, sql, params, timeout), s}
  end

  def handle_cast({:monitor, pid}, %{monitor: nil} = s) do
    ref = Process.monitor(pid)
    {:noreply, %{s | monitor: {pid, ref}}}
  end

  def handle_cast({:demonitor, pid}, %{monitor: {pid, ref}} = s) do
    Process.demonitor(ref)
    {:noreply, %{s | monitor: nil}}
  end

  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    {:noreply, %{s | conn: nil}}
  end

  def handle_info({:DOWN, ref, :process, pid, _info}, %{monitor: {pid, ref}} = s) do
    {:stop, :normal, s}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: nil}) do
    :ok
  end

  def terminate(_reason, %{conn: conn}) do
    Riak.Connection.stop(conn)
  end

  defp new_state do
    %{conn: nil, params: nil, monitor: nil}
  end

end
