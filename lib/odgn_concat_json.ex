defmodule ConcatJSON do
  @moduledoc """
  Documentation for OdgnConcatJson.
  """

  require Logger


  @default_counts %{pos: 0, line: 1, obj: 0, arr: 0, current: nil }


  @doc """
  Returns all
    iex> OdgnConcatJson.parse_all('{"ok": true }')
    {:ok, ['{"ok": true }'] }
  """
  def parse_all( value ) do
    parse_all( value, [], @default_counts )
  end

  @doc """

  """
  def parse_all( input, buffer, counts, results \\ [] )

  def parse_all( input, buffer, counts, results ) when is_list(input), do: parse_all( to_string(input), buffer, counts, results )

  def parse_all( input, buffer, counts, results ) do
    # Logger.debug("begin parse_all input #{String.length(input)} (#{input}) buffer (#{buffer})")
    parse_all_loop( input, Enum.reverse(buffer), counts, results )
  end


  defp parse_all_loop( input, buffer, counts, results ) do
    case parse( input, buffer, counts ) do
      {:ok, _input, [], _counts } ->
        {:ok, results }
      {:ok, "", value, _counts } ->
        {:ok, results ++ [value] }
      {:ok, input, value, counts} ->
          # Logger.debug(":ok parse_all input #{String.length(input)} (#{input}) buffer (#{buffer})")
          parse_all_loop( input, [], counts, results ++ [value] )

      {:continue, input, value, counts } ->
        {:continue, results, input, value, counts }
      other -> other
    end

  end


  @doc """

  inspiration from https://stackoverflow.com/a/29408700/2377677
  """
  def stream(enum) do
    enum
    |> Stream.transform( {}, fn(val,acc) ->
      # Logger.debug "val: (#{val})"
      # IO.puts "acc: #{Jason.encode!(acc)}"

      parse_result = case acc do
        {:continue, buffer, opts} ->
          # Logger.debug "continue with (#{val}) (#{buffer})"
          ConcatJSON.parse_all(val, buffer,opts)
        _ ->
          ConcatJSON.parse_all( val )
      end

      case parse_result do
        {:ok, results} ->
          # Logger.warn ":ok with #{length(results)} (#{results})"
          {results,{}}
        {:continue, [], _input, buffer, opts } ->
          # Logger.warn "continue with empty results true"
          {[], {:continue, buffer, opts} }
        {:continue, results, _input, buffer, opts } ->
          # Logger.warn "continue with (#{results}) #{results == []}"
          {results, {:continue, buffer, opts} }
        # {:error, _buffer, _input, _opts, msg } ->
          # Logger.warn "error: #{msg}"
          # {[], {:error, msg}}
        # parsed ->
        #   IO.inspect parsed
      end

      # {[val],acc}
    end)
  end

  @doc """
  Takes an enumeration and parses all of the values
  """
  def reduce(enum) do
    { result, _acc } = Enum.reduce(enum, { [], {} }, fn value, { result, acc } ->
      parse_result = case acc do
        {:continue, buffer, opts } ->
          ConcatJSON.parse_all(value, buffer, opts)
        _ -> ConcatJSON.parse_all(value)
      end

      case parse_result do
        {:ok, results} ->
          { result ++ results, {} }
        {:continue, [], _input, buffer, opts } ->
          {result, {:continue, buffer, opts} }
        {:continue, results, _input, buffer, opts } ->
          {result ++ results, {:continue, buffer, opts} }
      end
    end)
    result
  end



  defp parse(binary, acc , counts) do
    case walk_parse(binary, acc, counts) do
      {code, rest, acc, counts} -> {code, rest, Enum.reverse(acc), counts}
      # {:error, rest, acc, counts, msg} -> {:error, rest, Enum.reverse(acc), counts, msg}
      {:error, msg} -> {:error, msg}
    end
  end

  defp walk_parse(binary, acc, counts)

  defp walk_parse(binary, acc, counts) when is_binary(acc) do
    walk_parse(binary, Enum.reverse(to_charlist(acc)), counts)
  end

  defp walk_parse(binary, acc, counts) when is_list(binary) do
    walk_parse(to_string(binary), acc, counts)
  end

  defp walk_parse(binary, acc, counts) when binary == "" do
    # Logger.debug "walk_parse 4 - binary end (#{binary}) (#{acc})"
    # raise "STAHP"
    {:ok, binary, acc, counts}
  end

  defp walk_parse(<<"#", rest::binary>>, acc, %{pos: position} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: position + 1, current: :comment}) do
      {:ok, rest, acc, counts} -> walk_parse(rest, acc, counts)
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse(<<"//", rest::binary>>, acc, %{pos: position} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: position + 2, current: :comment}) do
      {:ok, rest, acc, counts} ->
        # Logger.debug "walk_parse 5 // :ok - (#{rest}) (#{acc})"
        walk_parse(rest, acc, counts)
      {:continue, rest, acc, counts} ->
        # Logger.debug "walk_parse 5 // :continue"
        {:continue, rest, acc, counts}
    end
  end

  defp walk_parse(<<"[", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("> walk_parse 6 '#{acc}' '[#{rest}'")

    case walk_parse_array(rest, '[' ++ acc, %{counts | pos: pos + 1, arr: 1, current: :array}) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, %{counts|current: nil}}
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse(<<"{", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse 7 (#{'{' ++ acc}) ({#{rest})")

    case walk_parse_obj(rest, '{' ++ acc, %{counts | pos: pos + 1, obj: 1, current: :obj}) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, %{counts|current: nil}}
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  # continues a partial parse of an obj, array, or string
  defp walk_parse(<<rest::binary>>, acc, %{pos: pos, obj: obj, arr: arr, current: current} = counts)
       when obj > 0 or arr > 0 or current == :string or current == :value do

    acc = Enum.reverse(acc)
    # Logger.debug("> walk_parse 7a (#{to_string(acc) <> rest})")

    case walk_parse(to_string(acc) <> rest, [], %{
           counts
           | pos: pos - length(acc),
             obj: 0,
             arr: 0,
             current: nil
         }) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, counts}
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  # continues a partial parse of a comment
  defp walk_parse(<<rest::binary>>, acc, %{pos: pos, current: current} = counts)
       when current == :comment do
    acc = Enum.reverse(acc)
    # Logger.debug("> walk_parse 7b '#{to_string(acc) <> rest}'")

    case walk_parse(to_string(acc) <> "#" <> rest, [], %{
           counts
           | pos: pos - length(acc),
             current: nil
         }) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, counts}
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse(<<ch, _rest::binary>>, _acc, %{pos: pos, line: line})
       when ch == ?] or ch == ?} do
    # {:error, rest, [ch] ++ acc, counts,
    #  "Unexpected token #{<<ch::utf8>>} at position #{pos} line #{line}"}
     {:error, "Unexpected token #{<<ch::utf8>>} at position #{pos} line #{line}"}
  end

  # begin parsing quote
  defp walk_parse(<<"\"", rest::binary>>, acc, %{pos: pos} = counts) do
    case walk_parse_quote(rest, '\"' ++ acc, %{counts | pos: pos + 1, current: :string}) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, %{counts|current: nil}}
      {code, rest, acc, counts} -> {code, rest, acc, counts}
    end
  end

  # newline - inc line number
  defp walk_parse(<<"\n", rest::binary>>, acc, %{line: line} = counts) do
    # Logger.debug "walk_parse 5 (#{acc}) rest:(#{rest})"
    walk_parse(rest, acc, %{counts | pos: 0, line: line + 1})
  end

  defp walk_parse(<<" ", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug "walk_parse space #{acc}"
    walk_parse(rest, acc, %{counts | pos: pos + 1})
  end

  # pass everything
  defp walk_parse(<<char, rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug "walk_parse char:(#{to_string([char])})"
    case walk_parse_value(rest, [char] ++ acc, %{counts| pos: pos + 1, current: :value}) do
      {:ok, rest, acc, counts} -> {:ok, rest, acc, %{counts|current: nil}}
      {code, rest, acc, counts} -> {code, rest, acc, counts}
    end
    # walk_parse(rest, [char] ++ acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_comment(<<"\n", rest::binary>>, acc, %{line: line} = counts) do
    # Logger.debug("walk_parse_comment 1 - :ok")
    {:ok, rest, acc, %{counts | line: line + 1, pos: 0, current: nil}}
  end

  defp walk_parse_comment(<<_char, rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_comment 2 ")
    walk_parse_comment(rest, acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_comment(binary, acc, counts) when binary == "" do
    # Logger.debug("walk_parse_comment 3 - :ok")
    {:continue, binary, acc, counts}
  end

  defp walk_parse_quote(<<(~s(\\")), rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_quote 1 #{acc} char:(#{~s(\\")})")
    walk_parse_quote(rest, '\"' ++ acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_quote(<<(~s(")), rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_quote 2 #{acc} - fin")
    {:ok, rest, '"' ++ acc, %{counts | pos: pos + 1}}
  end

  defp walk_parse_quote(<<char, rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_quote 3 (#{acc}) ++ (#{[char]})")
    walk_parse_quote(rest, [char] ++ acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_quote(binary, acc, counts) when binary == "" do
    # Logger.debug("walk_parse_quote 4 (#{acc}) (#{binary})")
    {:continue, binary, acc, counts}
  end


  # close array - finish if count ends, continue otherwise
  defp walk_parse_array(<<"]", rest::binary>>, acc, %{pos: pos, arr: arr} = counts) do
    # Logger.debug("walk_parse_array 2 #{acc} arr:#{arr}")
    acc = ']' ++ acc
    counts = %{counts | pos: pos + 1, arr: arr - 1}

    case arr do
      1 -> {:ok, rest, acc, counts}
      _ -> walk_parse_array(rest, acc, counts)
    end
  end

  defp walk_parse_array(<<"[", rest::binary>>, acc, %{pos: pos, arr: arr} = counts) do
    # Logger.debug("walk_parse_array 4 #{acc} arr: #{arr + 1}")
    walk_parse_array(rest, '[' ++ acc, %{counts | pos: pos + 1, arr: arr + 1})
  end

  defp walk_parse_array(<<"\"", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_array 5 #{acc}")

    case walk_parse_quote(rest, '"' ++ acc, %{counts | pos: pos + 1, current: :string}) do
      {:ok, rest, acc, counts} -> walk_parse_array(rest, acc, %{counts| current: :array})
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_array(<<"#", rest::binary>>, acc, %{pos: pos} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: pos + 1, current: :comment}) do
      {:ok, rest, acc, counts} -> walk_parse_array(rest, acc, %{counts|current: :array})
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_array(<<"//", rest::binary>>, acc, %{pos: position} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: position + 2, current: :comment}) do
      {:ok, rest, acc, counts} -> walk_parse_array(rest, acc, %{counts|current: :array})
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_array(<<"\n", rest::binary>>, acc, %{line: line} = counts) do
    # Logger.debug("walk_parse_array 6 #{acc}")
    walk_parse_array(rest, acc, %{counts | pos: 0, line: line + 1})
  end

  defp walk_parse_array(<<" ", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug "parse space #{acc}"
    walk_parse_array(rest, acc, %{counts | pos: pos + 1})
  end

  # everything else
  defp walk_parse_array(<<char, rest::binary>>, acc, %{pos: pos, arr: _arr} = counts) do
    # Logger.debug("walk_parse_array 7 (#{acc}) '#{to_string([char])}' arr:#{arr}")
    walk_parse_array(rest, [char] ++ acc, %{counts | pos: pos + 1})
  end

  # end of input
  defp walk_parse_array(binary, acc, counts) when binary == "" do
    # Logger.debug("walk_parse_array 8 #{acc}")
    {:continue, binary, acc, counts}
  end

  defp walk_parse_obj(<<"}", rest::binary>>, acc, %{pos: pos, obj: obj} = counts) when obj == 1 do
    acc = '}' ++ acc
    # Logger.debug("walk_parse_obj 2 (#{acc}) obj:#{obj} - :ok")
    {:ok, rest, acc, %{counts | pos: pos + 1, obj: obj - 1}}
  end

  defp walk_parse_obj(<<"}", rest::binary>>, acc, %{pos: pos, obj: obj} = counts) do
    # Logger.debug("walk_parse_obj 3 #{acc} obj:#{obj}")
    walk_parse_obj(rest, '}' ++ acc, %{counts | pos: pos + 1, obj: obj - 1})
  end

  defp walk_parse_obj(<<"#", rest::binary>>, acc, %{pos: pos} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: pos + 1, current: :comment}) do
      {:ok, rest, acc, counts} -> walk_parse_obj(rest, acc, counts)
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_obj(<<"//", rest::binary>>, acc, %{pos: position} = counts) do
    case walk_parse_comment(rest, acc, %{counts | pos: position + 2, current: :comment}) do
      {:ok, rest, acc, counts} -> walk_parse_obj(rest, acc, counts)
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_obj(<<"{", rest::binary>>, acc, %{pos: pos, obj: obj} = counts) do
    # Logger.debug("walk_parse_obj 4 #{acc} obj: #{obj + 1}")
    walk_parse_obj(rest, '{' ++ acc, %{counts | pos: pos + 1, obj: obj + 1})
  end

  defp walk_parse_obj(<<"\"", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug("walk_parse_obj 5 (#{acc})")

    case walk_parse_quote(rest, '"' ++ acc, %{counts | pos: pos + 1, current: :string}) do
      {:ok, rest, acc, counts} -> walk_parse_obj(rest, acc, counts)
      {:continue, rest, acc, counts} -> {:continue, rest, acc, counts}
    end
  end

  defp walk_parse_obj(<<"\n", rest::binary>>, acc, %{line: line} = counts) do
    # Logger.debug("walk_parse_obj 6 #{acc}")
    walk_parse_obj(rest, acc, %{counts | pos: 0, line: line + 1})
  end

  defp walk_parse_obj(<<" ", rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug "parse space #{acc}"
    walk_parse_obj(rest, acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_obj(<<char, rest::binary>>, acc, %{pos: pos, obj: _obj } = counts) do
    # Logger.debug("walk_parse_obj 7 (#{acc}) '#{to_string([char])}' obj:#{obj}")
    walk_parse_obj(rest, [char] ++ acc, %{counts | pos: pos + 1})
  end

  defp walk_parse_obj("", acc, counts) do
    # Logger.debug("walk_parse_obj 8 #{acc}")
    {:continue, "", acc, counts}
  end

  defp walk_parse_value("", acc, counts) do
    # Logger.debug("walk_parse_value :continue")
    {:continue, "", acc, counts}
  end

  # end of input
  defp walk_parse_value(<<char, rest::binary>>, acc, %{pos: pos} = counts) when char == ?\n or char == 32 do
    # Logger.debug "walk_parse_value newline/space :ok"
    {:ok, rest, acc, %{counts | pos: pos + 1}}
  end

  # space indicates end of value
  # defp walk_parse_value(<<" ", rest::binary>>, acc, %{pos: pos} = counts) do
  #   # Logger.debug "walk_parse_value :ok"
  #   {:ok, rest, acc, %{counts | pos: pos + 1}}
  # end

  # regular character
  defp walk_parse_value(<<char, rest::binary>>, acc, %{pos: pos} = counts) do
    # Logger.debug "walk_parse_value char:(#{to_string([char])})"
    walk_parse_value(rest, [char] ++ acc, %{counts | pos: pos + 1})
  end

  # def finish_ok(acc, rest, counts) do
  #   # IO.inspect( acc )
  #   {:ok, to_string(Enum.reverse(acc)), to_string(rest), counts}
  # end

  # def finish_continue(acc, rest, counts) do
  #   {:continue, to_string(Enum.reverse(acc)), to_string(rest), counts}
  # end

end
