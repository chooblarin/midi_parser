defmodule MidiParser do
  @moduledoc """
  Documentation for MidiParser.
  """

  @doc """
  Parsing MIDI file.
  """

  @chunk_type_header "MThd" # <<77, 84, 104, 100>>
  @chunk_type_track  "MTrk" # <<77, 84, 114, 107>>

  def parse(data) do
    {header, chunks} = extract_header(data)
    tracks = extract_tracks(chunks)
      |> Enum.map(fn x -> parse_track(x) end)

    {header, tracks}
  end

  def extract_header(<<
  @chunk_type_header,
  6 :: size(32),
  format :: size(16),
  num_of_tracks :: size(16),
  time_unit :: size(16),
  chunks :: binary>>) do

    header = %{
      format: format,
      num_of_tracks: num_of_tracks,
      time_unit: time_unit
    }

    {header, chunks}
  end

  def extract_tracks(data) do
    _extract_tracks(data, [])
  end

  defp _extract_tracks(<<>>, result) do
    Enum.reverse(result)
  end

  defp _extract_tracks(<<
  @chunk_type_track,
  length :: size(32),
  body :: binary - size(length),
  chunks :: binary>>, tracks) do

    _extract_tracks(chunks, [body | tracks])
  end

  def parse_track(body) do _parse_track(body, 0x00, []) end

  defp _parse_track(<<>>, _, result) do Enum.reverse(result) end

  defp _parse_track(body, prev, acc) do

    {delta_time, rest} = extract_variable_length(body)
    {event, chunks} = parse_event(rest, prev)
    case event do
      {:midi, status, _, _} ->
        _parse_track(chunks, status, [{delta_time, event} | acc])
      _ ->
        _parse_track(chunks, prev, [{delta_time, event} | acc])
    end
  end

  def extract_variable_length(data) do
    bits = _extract_variable_length(data)
    bs = bit_size(bits)
    padding_size = 8 - rem(bs, 8)
    byte_data = << <<0 :: size(padding_size)>> :: bitstring, bits :: bitstring >>

    bit_length = padding_size + bs
    <<length :: size(bit_length)>> = byte_data
    <<_ :: size(bit_length), chunks :: binary>> = data
    {length, chunks}
  end

  defp _extract_variable_length(<<msb :: 1, exp :: 7, _ :: binary>>) when msb == 0 do
    <<exp :: 7>>
  end

  defp _extract_variable_length(<<_ :: 1, exp :: 7, rest :: binary>>) do
    next = _extract_variable_length(rest)
    << <<exp :: 7>> :: bitstring, next :: bitstring >>
  end

  def parse_event(data, prev \\ 0x00)

  def parse_event(<<status, _ :: binary>> = data, _) when status in [0xF0, 0xF7] do
    handle_sysex_event(data)
  end

  def parse_event(<<status, _ :: binary>> = data, _) when status == 0xFF do
    handle_meta_event(data)
  end

  def parse_event(<<status, tail :: binary>> = data, prev) do
    <<msb :: size(1), _ :: size(7)>> = <<status>>
    case msb do
      0 -> # running-status
        <<note_num, velocity, chunks :: binary>> = data
        {{:midi, midi_event(prev), note_num, velocity}, chunks}

      1 ->
        <<note_num, velocity, chunks :: binary>> = tail
        {{:midi, midi_event(status), note_num, velocity}, chunks}
    end
  end

  def handle_sysex_event(<<0xF0, tail :: binary>>) do    
    {length, rest} = extract_variable_length(tail)
    <<message :: binary - size(length), 0xF7, chunks :: binary>> = rest
    {{:sysex, message}, chunks}
  end

  def handle_sysex_event(<<0xF7, tail :: binary>>) do
    {length, rest} = extract_variable_length(tail)
    <<message :: binary - size(length), chunks :: binary>> = rest
    {{:sysex, message}, chunks}
  end

  def handle_meta_event(<<_, tail :: binary>>) do
    <<meta_type, rest :: binary>> = tail
    {length, body_and_chunks} = extract_variable_length(rest)
    <<meta_data :: binary - size(length), chunks :: binary>> = body_and_chunks
    {{:meta, meta_type, meta_data}, chunks}
  end

  def handle_midi_event(<<type, tail :: binary>>) do
    event = midi_event(type)
    <<note_num, velocity, chunks :: binary>> = tail
    {{:midi, event, note_num, velocity}, chunks}
  end

  defp midi_event(x) when x in 0x80..0x8f do :note_off end
  defp midi_event(x) when x in 0x90..0x9f do :note_on end
  defp midi_event(x) when x in 0xb0..0xbf do :ctrl_change end
  defp midi_event(_) do :unknown end  # todo: I don't know exactly
end
