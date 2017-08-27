defmodule MidiParserTest do
  use ExUnit.Case
  doctest MidiParser

  test "extract variable-length part" do
    {x, rest} = MidiParser.extract_variable_length(<<0x00, 0x88>>)
    assert x == 0
    assert rest == <<0x88>>

    {x, _} = MidiParser.extract_variable_length(<<0x7F>>)
    assert x == 0x7F
    {x, _} = MidiParser.extract_variable_length(<<0x81, 0x00>>)
    assert x == 0x80
    {x, _} = MidiParser.extract_variable_length(<<0xC0, 0x00>>)
    assert x == 0x00002000
    {x, _} = MidiParser.extract_variable_length(<<0xFF, 0xFF, 0x7F>>)
    assert x == 0x001FFFFF
    {x, _} = MidiParser.extract_variable_length(<<0xFF, 0xFF, 0xFF, 0x7F>>)
    assert x == 0x0FFFFFFF
  end

  test "parse SysEX event of track (exclusive message)" do
    data = <<240, 6, 78, 111, 105, 122, 101, 49, 247>>
    {{:sysex, message}, rest} = MidiParser.handle_sysex_event(data)
    assert message == <<78, 111, 105, 122, 101, 49>>
    assert rest == <<>>
  end

  test "parse SysEX event of track (arbitrary message)" do
    data = <<247, 6, 78, 111, 105, 122, 101, 49>>
    {{:sysex, message}, rest} = MidiParser.handle_sysex_event(data)
    assert message == <<78, 111, 105, 122, 101, 49>>
    assert rest == <<>>
  end

  test "parse meta event of track" do
    data = <<255, 3, 6, 78, 111, 105, 122, 101, 49>>
    {{:meta, type, body}, rest} = MidiParser.handle_meta_event(data)
    assert type == 3
    assert body == <<78, 111, 105, 122, 101, 49>>
    assert rest == <<>>
  end

  test "parse midi event of track" do
    note_on_data = <<0x90, 0x2D, 0x5A>>
    {{:midi, event, note_num, velocity}, rest} = MidiParser.parse_event(note_on_data)
    assert event == :note_on
    assert note_num == 0x2D
    assert velocity == 0x5A
    assert rest == <<>>

    note_off_data = <<0x80, 0x2D, 0x00>>
    {{:midi, event, note_num, velocity}, rest} = MidiParser.parse_event(note_off_data)
    assert event == :note_off
    assert note_num == 0x2D
    assert velocity == 0x00
    assert rest == <<>>

    running_status_data = <<0x2C, 0x01>>
    {{:midi, event, note_num, velocity}, rest} = MidiParser.parse_event(running_status_data, 0x80)
    assert event == :note_off
    assert note_num == 0x2C
    assert velocity == 0x01
    assert rest == <<>>
  end

  test "parse track body (including running status)" do
    data = <<
    0, 255, 3, 4, 80, 101, 114, 99, 141, 151, 64, 153, 44, 83, 94, 137,
    44, 0, 26, 153, 42, 90, 110, 137, 42, 0, 10, 153, 44, 94, 107, 137,
    44, 0, 13, 153, 42, 99, 120, 44, 105, 19, 137, 42, 0, 101, 153, 42,
    110, 8, 137, 44, 0, 112, 153, 44, 116, 10, 137, 42, 0, 103, 44, 0, 7,
    153, 42, 124, 125, 137, 42, 0, 0, 255, 47, 0
    >>

    track = MidiParser.parse_track(data)
    midi_count = track
      |> Enum.filter(fn ({_, event}) -> elem(event, 0) == :midi end)
      |> Enum.count

    assert midi_count == 16
  end
end
