defmodule OdgnConcatJsonTest do
  use ExUnit.Case
  # doctest OdgnConcatJson
  alias ConcatJSON
  require Logger

  test "strings" do
    # complete string
    assert ConcatJSON.parse_all(~s("hello")) == {:ok, ['"hello"']}

    # incomplete string
    assert ConcatJSON.parse_all(~s("hello)) ==
             {:continue, [], "", '"hello', %{arr: 0, current: :string, line: 1, obj: 0, pos: 6}}

    # newlines are retained in strings
    assert ConcatJSON.parse_all(~s("good \nnews")) ==
             {:ok, ['"good \nnews"']}

    # escaped quotes
    assert ConcatJSON.parse_all(~s("\\"hello \\"world\\"\\"")) ==
             {:ok, ['""hello "world"""']}
  end

  test "values" do
    assert ConcatJSON.parse_all(~s( 2 )) == {:ok, ['2']}
    assert ConcatJSON.parse_all(~s( true )) == {:ok, ['true']}

    assert ConcatJSON.parse_all(~s(true )) == {:ok, ['true']}
    assert ConcatJSON.parse_all(~s(true\n)) == {:ok, ['true']}

    assert ConcatJSON.parse_all(~s( ), 'true\n', %{
             arr: 0,
             current: :value,
             line: 1,
             obj: 0,
             pos: 5
           }) ==
             {:ok, ['true']}

    assert ConcatJSON.parse_all(~s(true 23.45 -1 0.2 [ 6, 7, 8] { "msg": true } )) ==
             {:ok, ['true', '23.45', '-1', '0.2', '[6,7,8]', '{"msg":true}']}

    # without a terminator, the parse cannot finish
    assert ConcatJSON.parse_all("super") ==
             {:continue, [], "", 'super', %{arr: 0, current: :value, line: 1, obj: 0, pos: 5}}

    assert ConcatJSON.parse_all("star\n", 'super', %{
             arr: 0,
             current: :value,
             line: 1,
             obj: 0,
             pos: 5
           }) ==
             {:ok, ['superstar']}

    # comment chars included
    assert ConcatJSON.parse_all("foo// nothing good\n") ==
             {:ok, ['foo//', 'nothing', 'good']}
  end

  test "objects" do
    # empty object
    assert ConcatJSON.parse_all(~s({})) ==
             {:ok, ['{}']}

    # basic object
    assert ConcatJSON.parse_all(~s({ "ok": true })) == {:ok, ['{"ok":true}']}

    # # ignores newlines
    assert ConcatJSON.parse_all(~s({ "msg":\n "hello" })) == {:ok, ['{"msg":"hello"}']}
  end

  test "arrays" do
    # empty array
    assert ConcatJSON.parse_all(~s([])) ==
             {:ok, ['[]']}

    assert ConcatJSON.parse_all(~s([ "hello"])) == {:ok, ['["hello"]']}

    # incomplete array
    assert ConcatJSON.parse_all(~s([ "one", )) ==
             {:continue, [], "", '["one",', %{arr: 1, pos: 9, line: 1, obj: 0, current: :array}}

    assert ConcatJSON.parse_all(~s("two" ]), '["one",', %{
             arr: 1,
             pos: 9,
             line: 1,
             obj: 0,
             current: nil
           }) ==
             {:ok, ['["one","two"]']}
  end

  test "comments" do
    assert ConcatJSON.parse_all(~s(# elixir style)) ==
             {:continue, [], "", [], %{arr: 0, current: :comment, line: 1, obj: 0, pos: 14}}

    assert ConcatJSON.parse_all(~s(// js style)) ==
             {:continue, [], "", [], %{arr: 0, current: :comment, line: 1, obj: 0, pos: 11}}

    assert ConcatJSON.parse_all(~s(# js style\n "fine")) ==
             {:ok, ['"fine"']}

    assert ConcatJSON.parse_all(~s(// js style\n "fine")) ==
             {:ok, ['"fine"']}

    # comments within object
    assert ConcatJSON.parse_all(~s({ "hello": # ignore this\n "world"})) ==
             {:ok, ['{"hello":"world"}']}

    # # comments within array
    assert ConcatJSON.parse_all(~s([ "hello", 2, 3 # ignore this\n, "world"])) ==
             {:ok, ['["hello",2,3,"world"]']}

    # incomplete comment
    assert ConcatJSON.parse_all(~s("good" #)) ==
             {:continue, ['"good"'], "", [],
              %{arr: 0, current: :comment, line: 1, obj: 0, pos: 8}}

    assert ConcatJSON.parse_all(~s( comment] continues\n), '', %{
             arr: 0,
             current: :comment,
             line: 1,
             obj: 0,
             pos: 8
           }) ==
             {:ok, []}
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

    assert ConcatJSON.parse_all(a) ==
             {:continue, ['{"foo":"bar"}'], "", '{"',
              %{arr: 0, line: 3, obj: 1, pos: 6, current: :string}}

    assert ConcatJSON.parse_all(b, '{"', %{arr: 0, line: 3, obj: 1, pos: 6, current: nil}) ==
             {:continue, ['{"qux":"corge"}'], "", '{"baz":{',
              %{arr: 0, line: 6, obj: 2, pos: 4, current: :string}}

    assert ConcatJSON.parse_all(c, '{"baz":{', %{arr: 0, line: 6, obj: 2, pos: 4, current: nil}) ==
             {:ok, ['{"baz":{"waldo":"thud"}}']}

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

    assert ConcatJSON.parse_all(a) ==
             {:ok, ['{"foo":"bar"}']}

    assert ConcatJSON.parse_all(b) ==
             {:continue, ['{"qux":"corge"}'], "", '{"baz":',
              %{arr: 0, line: 3, obj: 1, pos: 15, current: :string}}

    assert ConcatJSON.parse_all(c, '{"baz":', %{arr: 0, line: 3, obj: 1, pos: 15, current: nil}) ==
             {:continue, [], "", '{"baz":{"waldo":"thud"',
              %{arr: 0, line: 5, obj: 1, pos: 1, current: :string}}

    assert ConcatJSON.parse_all(d, '{"baz":{"waldo":"thud"', %{
             arr: 0,
             line: 5,
             obj: 1,
             pos: 1,
             current: nil
           }) ==
             {:ok, ['{"baz":{"waldo":"thud"}}']}
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
             {:continue, [], "", '["hello"', %{arr: 1, line: 1, obj: 0, pos: 9, current: :array}}

    assert ConcatJSON.parse_all(', "world"]', '["hello"', %{
             arr: 1,
             line: 1,
             obj: 0,
             pos: 9,
             current: nil
           }) == {:ok, ['["hello","world"]']}
  end

  test "stream" do
    output =
      File.stream!("./test/data/a.json", [], 8)
      |> ConcatJSON.stream()
      |> Enum.to_list()

    # |> Stream.map( fn(json) -> Jason.decode!(json) end)
    # |> Enum.each(fn x -> IO.puts( ">>> result #{Jason.encode!(x)}") end)
    # |> Enum.each(fn x -> IO.puts( ">>> result #{x}") end)
    # |> Enum.each(fn x -> IO.puts( ">>> result"); IO.inspect(x) end)

    assert output == ['{"foo":"bar"}', '{"qux":"corge"}', '{"baz":{"waldo":"thud"}}']
  end

  test "reduce" do

    output = [ '{"some":"thing\n"}', '{"may" : { "include":"nest', 'ed" , "objects" : [ "and" , "arrays" ]}}' ]
    |> ConcatJSON.reduce

    assert output == ['{"some":"thing\n"}', '{"may":{"include":"nested","objects":["and","arrays"]}}']

  end

  test "errors" do
    assert ConcatJSON.parse_all(~s(\n ])) ==
             {:error, "Unexpected token ] at position 1 line 2"}

    assert ConcatJSON.parse_all(~s(})) ==
             {:error, "Unexpected token } at position 0 line 1"}

    assert ConcatJSON.parse_all(~s([]])) ==
             {:error, "Unexpected token ] at position 2 line 1"}
  end
end
