defmodule MerklePatriciaTree.Trie.Node do
  @moduledoc """
  This module encodes and decodes nodes from a
  trie encoding back into RLP form. We effectively implement
  `c(I, i)` from the Yellow Paper.

  TODO: Add richer set of tests, esp. in re: storage and branch values.
  """

  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Trie.Storage
  alias MerklePatriciaTree.DB
  alias MerklePatriciaTree.Utils

  @type trie_node ::
          :empty
          | {:leaf, [integer()], binary()}
          | {:ext, [integer()], binary()}
          | {:branch, [binary()]}

  @doc """
  Given a node, this function will encode the node
  and put the value to storage (for nodes that are
  greater than 32 bytes encoded). This implements
  `c(I, i)`, Eq.(179) of the Yellow Paper.

  ## Examples

  iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db())
  iex> MerklePatriciaTree.Trie.Node.encode_node(:empty, trie)
  <<>>

  iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db())
  iex> MerklePatriciaTree.Trie.Node.encode_node({:leaf, [5,6,7], "ok"}, trie)
  ["5g", "ok"]

  iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db())
  iex> MerklePatriciaTree.Trie.Node.encode_node({:branch, [<<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>]}, trie)
  ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]

  iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db())
  iex> MerklePatriciaTree.Trie.Node.encode_node({:ext, [1, 2, 3], <<>>}, trie)
  [<<17, 35>>, ""]
  """
  @spec encode_node(trie_node, Trie.t()) :: nil | binary()
  def encode_node(trie_node, trie) do
    trie_node
    |> encode_node_type(trie)
    |> Storage.put_node(trie)
  end

  @spec decode_node(list(), Trie.t()) :: trie_node
  def decode_node(branches, trie) when length(branches) == 17 do
    {:branch,
     Enum.reduce(branches, [], fn
       "", acc ->
         acc ++ [""]

       elem, acc when is_binary(elem) and byte_size(elem) == 32 ->
         {:ok, node} = DB.get(trie.db, elem)
         acc ++ [ExRLP.decode(node)]

       elem, acc when is_binary(elem) ->
         acc ++ [ExRLP.decode(elem)]
     end)}
  end

  def decode_node([hp_k, v], _trie) do
    {prefix, is_leaf} = HexPrefix.decode(hp_k)

    if is_leaf do
      {:leaf, prefix, v}
    else
      {:ext, prefix, v}
    end
  end

  defp encode_node_type({:leaf, key, value}, _trie) do
    [HexPrefix.encode({key, true}), value]
  end

  defp encode_node_type({:branch, branches}, trie) when length(branches) == 17 do
    Enum.reduce(branches, [], fn
      "", acc ->
        acc ++ [""]

      elem, acc when is_list(elem) ->
        encoded_elem = ExRLP.encode(elem)

        if byte_size(encoded_elem) < 32 do
          acc ++ [encoded_elem]
        else
          hash = Utils.hash(encoded_elem)
          DB.put!(trie.db, hash, encoded_elem)
          acc ++ [hash]
        end

      elem, acc ->
        acc ++ [elem]
    end)
  end

  defp encode_node_type({:ext, shared_prefix, next_node}, trie) when is_list(next_node) do
    encode_node_type({:ext, shared_prefix, ExRLP.encode(next_node)}, trie)
  end

  defp encode_node_type({:ext, shared_prefix, next_node}, trie) do
    if byte_size(next_node) == 32 do
      [HexPrefix.encode({shared_prefix, false}), next_node]
    else
      hash = Utils.hash(next_node)
      MerklePatriciaTree.DB.put!(trie.db, hash, next_node)
      [HexPrefix.encode({shared_prefix, false}), hash]
    end
  end

  defp encode_node_type(:empty, _trie), do: ""

  @doc """
  Decodes the root of a given trie, effectively
  inverting the encoding from `c(I, i)` defined in
  Eq.(179) fo the Yellow Paper.

  ## Examples

  iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Utils.random_ets_db(), <<128>>)
  iex> |> MerklePatriciaTree.Trie.Node.decode_trie()
  :empty

  iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Utils.random_ets_db(), <<198, 130, 53, 103, 130, 111, 107>>)
  iex> |> MerklePatriciaTree.Trie.Node.decode_trie()
  {:leaf, [5,6,7], "ok"}

  iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Utils.random_ets_db(), <<209, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>)
  iex> |> MerklePatriciaTree.Trie.Node.decode_trie()
  {:branch, [<<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>]}

  iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Utils.random_ets_db(), <<196, 130, 17, 35, 128>>)
  iex> |> MerklePatriciaTree.Trie.Node.decode_trie()
  {:ext, [1, 2, 3], <<>>}
  """
  @spec decode_trie(Trie.t()) :: trie_node
  def decode_trie(trie) do
    case Storage.get_node(trie) do
      nil ->
        :empty

      <<>> ->
        :empty

      :not_found ->
        :empty

      node ->
        decode_node(node, trie)
    end
  end
end
