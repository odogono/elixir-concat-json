defmodule OdgnConcatJsonTest do
  use ExUnit.Case
  # doctest OdgnConcatJson
  alias ConcatJSON
  require Logger

  test "greets the world" do
    assert ConcatJSON.hello() == :world
  end

  test "strings" do
    # complete string
    assert ConcatJSON.parse_all(~s("hello")) == {:ok, ['"hello"']}

    # incomplete string
    assert ConcatJSON.parse_get_result(~s("hello)) == {:continue, ~s("hello)}

    # newlines are retained in strings
    assert ConcatJSON.parse_get_result(~s("good \nnews")) == {:ok, ~s("good \nnews")}

    # escaped quotes
    assert ConcatJSON.parse_get_result(~s("\\"hello \\"world\\"\\"")) ==
             {:ok, ~s("\"hello \"world\"\"")}
  end

  test "values" do
    assert ConcatJSON.parse_all( ~s( 2 ) ) == { :ok, ~s(2) }
  end

  test "objects" do
  end

  test "arrays" do
    # incomplete array
    assert ConcatJSON.parse_all(~s([ "one", )) ==
      {:continue, [], "", '["one",',
        %{arr: 1, pos: 9, comment: false, line: 1, obj: 0, string: false}}

    assert ConcatJSON.parse_all(~s("two" ]), '["one",', %{
              arr: 1,
              pos: 9,
              comment: false,
              line: 1,
              obj: 0,
              string: false
            }) ==
            {:ok, ['["one","two"]']}
  end

  test "comments" do
    assert ConcatJSON.parse_get_result(~s(# elixir style)) == {:continue, ""}
    assert ConcatJSON.parse_get_result(~s(// js style)) == {:continue, ""}

    assert ConcatJSON.parse_get_result(~s(# js style\n "fine")) == {:ok, "\"fine\"" }
    assert ConcatJSON.parse_get_result(~s(// js style\n "fine")) == {:ok, "\"fine\"" }

    # comments within object
    assert ConcatJSON.parse_get_result(~s({ "hello": # ignore this\n "world"})) ==
        {:ok, ~s({"hello":"world"}) }

    # # comments within array
    assert ConcatJSON.parse_get_result(~s([ "hello", 2, 3 # ignore this\n, "world"])) ==
        {:ok, ~s(["hello",2,3,"world"]) }

    # incomplete comment
    assert ConcatJSON.parse_all( ~s("good" #))
      == {:continue, ['"good"'], "", [], %{arr: 0, comment: true, line: 1, obj: 0, pos: 8, string: false}}
    assert ConcatJSON.parse_all( ~s( comment] continues\n), '', %{arr: 0, comment: true, line: 1, obj: 0, pos: 8, string: false} )
      == {:ok, []}
  end

  test "continues" do
    a = ~s({"foo":"bar"}
    // ignore this
    {")
    b = ~s(qux":"corge"}
    {
        "baz": {
    )
    c = ~s(        "waldo":"thud"
  }
})

    # vals = [ a, b, c ]

  assert ConcatJSON.parse_all( a )
    == {:continue, ['{"foo":"bar"}'], "", '{"', %{arr: 0, comment: false, line: 3, obj: 1, pos: 6, string: false}}

  assert ConcatJSON.parse_all( b, '{"', %{arr: 0, comment: false, line: 3, obj: 1, pos: 6, string: false} )
    == {:continue, ['{"qux":"corge"}'], "", '{"baz":{', %{arr: 0, comment: false, line: 6, obj: 2, pos: 4, string: false}}

  assert ConcatJSON.parse_all( c, '{"baz":{', %{arr: 0, comment: false, line: 6, obj: 2, pos: 4, string: false} )
    == {:ok, ['{"baz":{"waldo":"thud"}}']}

    a = ~s({"foo":"bar"}
    // ignore this
)
    b = ~s({"qux":"corge"}
    {
        "baz": )

    c = ~s({
      "waldo":"thud"
 )
    d = ~s( }
    })

    assert ConcatJSON.parse_all( a )
    == {:ok, ['{"foo":"bar"}'] }

    assert ConcatJSON.parse_all( b )
    == {:continue, ['{"qux":"corge"}'], "", '{"baz":', %{arr: 0, comment: false, line: 3, obj: 1, pos: 15, string: false}}

    assert ConcatJSON.parse_all( c, '{"baz":', %{arr: 0, comment: false, line: 3, obj: 1, pos: 15, string: false})
    == {:continue, [], "", '{"baz":{"waldo":"thud"', %{arr: 0, comment: false, line: 5, obj: 1, pos: 1, string: false}}

    # Logger.info "><><><"

    assert ConcatJSON.parse_all( d, '{"baz":{"waldo":"thud"', %{arr: 0, comment: false, line: 5, obj: 1, pos: 1, string: false})
    == {:ok, ['{"baz":{"waldo":"thud"}}']}

  end

  test "parse all" do
    data = '{"foo":"bar"}{"qux":"corge"}{"baz":{"waldo":"thud"}'
    {:continue, results, _input, buffer, opts} = ConcatJSON.parse_all(data)

    assert results == ['{"foo":"bar"}', '{"qux":"corge"}']
    # IO.inspect results

    # IO.puts buffer
    # IO.inspect ConcatJSON.parse( '}', buffer, opts )
    assert ConcatJSON.parse_all('}', buffer, opts) == {:ok, ['{"baz":{"waldo":"thud"}}']}

    assert ConcatJSON.parse_all('[ "hello"') ==
             {:continue, [], "", '["hello"',
              %{arr: 1, comment: false, line: 1, obj: 0, pos: 9, string: false}}

    assert ConcatJSON.parse_all(', "world"]', '["hello"', %{
             arr: 1,
             comment: false,
             line: 1,
             obj: 0,
             pos: 9,
             string: false
           }) == {:ok, ['["hello","world"]']}
  end

  test "stream" do

    output = File.stream!("./test/data/a.json", [], 8)
    |> ConcatJSON.stream
    |> Enum.to_list()
      # |> Stream.map( fn(json) -> Jason.decode!(json) end)
      # |> Enum.each(fn x -> IO.puts( ">>> result #{Jason.encode!(x)}") end)
      # |> Enum.each(fn x -> IO.puts( ">>> result #{x}") end)
      # |> Enum.each(fn x -> IO.puts( ">>> result"); IO.inspect(x) end)

    assert output == ['{"foo":"bar"}', '{"qux":"corge"}', '{"baz":{"waldo":"thud"}}']

    # data = [
    #   '{"foo":"bar"}{"qux":"corge"}{"baz":{"waldo":"thud"}}'
    # ]
    # sub = Stream.uniq_by([{1, :x}, {2, :y}, {1, :z}], fn {x, _} -> x end) # |> Enum.to_list() |> IO.inspect

    # IO.inspect ub = uniq_by([{1, :x}, {2, :y}, {1, :z}], fn {x, _} -> x end)

    # data = ['"hello"', '[ 3, 4, 5]', '{ "msg": true }']

    # result =
    #   data
    #   |> Stream.transform([], fn val, acc ->
    #     IO.puts("val:#{val}")
    #     IO.puts("acc:#{acc}")

    #     case {val, acc} do
    #       # {^stop, []}                         -> {[]   , []           }
    #       # {^stop, [_|rest] = buf}             -> {[buf], rest         }
    #       # {val  , buf} when length(buf) < n+1 -> {[]   , buf ++ [val] }
    #       # {val  , [_|rest] = buf}             -> {[buf], rest ++ [val]}
    #       # {val, [_|rest] = buf} ->
    #       # IO.puts "   outputting #{rest}"
    #       # {[rest], buf ++ [val]}
    #       {val, []} -> {[val, "poop"], []}
    #     end
    #   end)
    #   # Enum.each(fn x -> IO.puts( ">>> result #{x}") end)
    #   |> Enum.to_list()

    # IO.puts ">>> result:"
    # result = data |> stream |> Enum.each(fn x -> IO.puts( ">>> result #{x}") end)

    # IO.inspect(result)
  end

  # defp mister_stream( input ) do
  #   IO.inspect( input )
  #   IO.puts "mister_stream #{input}"
  # end

  test "stuff" do
    # assert parse(~s({ "@cmd": "register", "uri": "/component/piece/king" })) ==
    #          {:ok, ~s({ "@cmd": "register", "uri": "/component/piece/king" }), "",
    #           %{arr: 0, line: 1, obj: 0, pos: 54}}

    # the parsing of an object was incomplete, so the accumulated string is passed back
    # assert parse(~s({ "hello": "}", "ok": true)) ==
    #   {:continue, "", '{ "hello": "}", "ok": true', %{arr: 0, line: 1, obj: 1, pos: 26}}

    # assert parse( ~s(}), '{ "hello": "}", "ok": true', %{arr: 0, line: 1, obj: 1, pos: 26}) ==
    #     {:ok, "", '{ "hello": "}", "ok": true}', %{arr: 0, line: 1, obj: 0, pos: 27}}

    # IO.inspect(@default_counts)

              # %{arr: 0, pos: 16, comment: false, line: 1, obj: 0, string: false}}

    # incomplete string
    # assert parse( ~s("hello ))
    #   == {:continue, "", '"hello ', %{arr: 0, line: 1, obj: 0, pos: 7, comment: false, string: true}}
    # assert parse( ~s(world"), '"hello ', %{arr: 0, line: 1, obj: 0, pos: 7, comment: false, string: true} )
    #   == {:ok, "", '"hello world"', %{arr: 0, comment: false, line: 1, obj: 0, pos: 13, string: false}}


    # # an object was parsed, with the remainder also passed back
    # assert parse(~s({ "hello":\n "}" }\n{ "ok": true })) ==
    #          {:ok, ~s(\n{ "ok": true }), '{ "hello": "}" }',
    #           %{arr: 0, line: 2, obj: 0, pos: 6}}

    # assert parse(~s({ "hello": # ignore this\n "world"})) ==
    #          {:ok, "", '{ "hello":  "world"}', %{arr: 0, line: 2, obj: 0, pos: 9}}

    # assert parse(~s({
    #   "@cmd": "register",
    #   "uri":"/component/position",
    #   "properties":[
    #       { "name":"file", "type": "string" },
    #       { "name":"rank", "type": "integer" }
    #   ] })) ==
    #          {:ok, "",
    #           '{      "@cmd": "register",      "uri":"/component/position",      "properties":[          { "name":"file", "type": "string" },          { "name":"rank", "type": "integer" }      ] }',
    #           %{arr: 0, line: 7, obj: 0, pos: 9}}



    # # basic object
    # assert parse_get_result(~s({ "ok": true }) ) == {:ok, ~s({ "ok": true }) }

    # multiple objects
    # {:ok, remainder, '{ "msg": "hello" }', counts } = parse( ~s({ "msg": "hello" } { "ok": true }))
    # assert remainder == " { \"ok\": true }"
    # assert parse( remainder, [], counts ) == {:ok, "", ' { "ok": true }', %{arr: 0, line: 1, obj: 0, pos: 33} }

    # invalid JSON
    # assert parse( ~s( what the }) ) == {:error, "", ' what the }', %{arr: 0, line: 1, obj: 0, pos: 10}, "Unexpected token } at position 10 line 1"}
    # assert parse( ~s(not great ] ]) ) == {:error, " ]", 'not great ]', %{arr: 0, line: 1, obj: 0, pos: 10}, "Unexpected token ] at position 10 line 1"}

    # # ignores newlines
    # assert parse_get_result(~s({ "msg":\n "hello" }) ) == {:ok, ~s({ "msg": "hello" }) }

    # # basic array
    # assert parse_get_result( ~s([ "hello"]) ) == {:ok, ~s([ "hello"]) }

    # assert parse(~s(\n{ "ok": true }), "", %{arr: 0, line: 2, obj: 1, pos: 6}) ==
    #     {:ok, "", '{ "ok": true }', %{arr: 0, line: 3, obj: 0, pos: 14}}

    # incomplete array - :complete is returning which implies further input needed
    # assert parse( ~s([ "hello", ) )
    #     == {:continue, "", '[ "hello", ', %{ arr: 1, line: 1, obj: 0, pos: 11} }

    # assert parse( ~s([ "hello"] [ "world" ] ) )
    #     == {:ok, ~s( [ "world" ] ), '[ "hello"]', %{ arr: 0, line: 1, obj: 0, pos: 10} }

    # IO.inspect Jason.decode!('[ "hello"]' )
  end
end
