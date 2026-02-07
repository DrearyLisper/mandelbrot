defmodule Mandelbrot.TileCache do
  @moduledoc """
  Fixed-size LRU cache for computed tile PNGs.

  Uses an ETS table for fast concurrent reads and a GenServer
  for maintaining LRU order and evicting entries when full.
  """
  use GenServer

  @default_max_size 1024
  @table :tile_cache

  # --- Public API ---

  def start_link(opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    GenServer.start_link(__MODULE__, max_size, name: __MODULE__)
  end

  @doc """
  Look up a cached tile. Returns {:ok, png} on hit, :miss on miss.
  Reads directly from ETS (concurrent, no GenServer call).
  On hit, asynchronously updates LRU order.
  """
  def get(z, x, y, dpr) do
    key = {z, x, y, dpr}

    case :ets.lookup(@table, key) do
      [{^key, png}] ->
        # Async touch — move to front of LRU order
        GenServer.cast(__MODULE__, {:touch, key})
        {:ok, png}

      [] ->
        :miss
    end
  end

  @doc """
  Store a tile in the cache. Evicts the least recently used
  entry if the cache is full.
  """
  def put(z, x, y, dpr, png) do
    GenServer.cast(__MODULE__, {:put, {z, x, y, dpr}, png})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(max_size) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{max_size: max_size, order: []}}
  end

  @impl true
  def handle_cast({:touch, key}, state) do
    # Move key to front of order list
    order = [key | List.delete(state.order, key)]
    {:noreply, %{state | order: order}}
  end

  def handle_cast({:put, key, png}, state) do
    :ets.insert(@table, {key, png})

    # Add to front, remove any previous occurrence
    order = [key | List.delete(state.order, key)]

    # Evict if over max size
    {order, state} = maybe_evict(order, state)

    {:noreply, %{state | order: order}}
  end

  defp maybe_evict(order, %{max_size: max_size} = state) when length(order) > max_size do
    {evict_key, rest} = List.pop_at(order, -1)
    :ets.delete(@table, evict_key)
    {rest, state}
  end

  defp maybe_evict(order, state), do: {order, state}
end
