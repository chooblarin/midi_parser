defmodule MidiParser do
  @moduledoc """
  Documentation for MidiParser.
  """

  @doc """
  Parsing MIDI file.
  """

  @chunk_type_header "MThd" # <<77, 84, 104, 100>>
  @chunk_type_track  "MTrk" # <<77, 84, 114, 107>>

  def parse(<<
  @chunk_type_header,
  6 :: size(32),
  format :: size(16),
  num_of_tracks :: size(16),
  time_unit :: size(16),
  chunks :: binary>>) do

    parse_track_chunks(chunks, [])
  end

  def parse_track_chunks(<<
  @chunk_type_track,
  length :: size(32),
  chunk_data :: binary - size(length),
  chunks :: binary>>, tracks) do

    track = parse_track_chunk(chunk_data)
    parse_track_chunks(chunks, [track | tracks])
  end
  def parse_track_chunks(<<>>, tracks) do
    Enum.reverse(tracks)
  end

  def parse_track_chunk(body) do parse_track_chunk(body, 0x00, []) end

  defp parse_track_chunk(<<>>, prev, acc) do Enum.reverse acc end
  defp parse_track_chunk(body, prev, acc) do

    {delta_time, rest} = parse_variable_length_data(body)
    {value, rest_chunk} = parse_event(rest, prev)

    case value do
      {:midi, type, _, _} ->
        parse_track_chunk(rest_chunk, type, [{delta_time, value} | acc])
      _ ->
        parse_track_chunk(rest_chunk, prev, [{delta_time, value} | acc])
    end
  end

  def parse_variable_length_data(data) do
    byte_length = variable_length_bytes(data)
    <<chunk :: binary - size(byte_length), chunks :: binary>> = data

    b = variable_length_data(chunk)
    bit_length = 8 * byte_length
    padding_size = bit_length - bit_size(b)
    byte_data = << <<0 :: size(padding_size)>> :: bitstring, b :: bitstring >>
    <<value :: size(bit_length)>> = byte_data

    {value, chunks}
  end

  def variable_length_bytes(<<msb :: size(1), _ :: size(7), rest :: binary>>) do
    case msb do
      0 -> 1
      1 -> 1 + variable_length_bytes(rest)
    end
  end
  def variable_length_bytes(<<>>) do 0 end

  defp variable_length_data(<<msb :: size(1), data :: size(7), rest :: binary>>) do
    case msb do
      0 -> <<data :: 7>>
      1 ->
        next = variable_length_data(rest)
        << <<data :: 7>> :: bitstring, next :: bitstring>>
    end
  end
  defp variable_length_data(<<_ :: binary>>) do <<>> end

  def parse_event(<<status, _ :: binary>> = data, _) when status in [0xF0, 0xF7] do
    handle_sysex_event(data)
  end

  def parse_event(<<status, _ :: binary>> = data, _) when status == 0xFF do
    handle_meta_event(data)
  end

  def parse_event(<<status, tail :: binary>> = data, prev \\ 0x00) do
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
    {length, rest} = parse_variable_length_data(tail)
    message_length = length - 1
    <<message :: binary - size(length), 0xF7, chunks :: binary>> = rest
    {
      {:sysex, message},
      chunks
    }
  end

  def handle_sysex_event(<<0xF7, tail :: binary>>) do
    {length, rest} = parse_variable_length_data(tail)
    <<message :: binary - size(length), chunks :: binary>> = rest
    {
      {:sysex, message},
      chunks
    }
  end

  def handle_meta_event(<<_, tail :: binary>>) do
    <<meta_type, rest :: binary>> = tail
    {length, body_and_chunks} = parse_variable_length_data(rest)
    <<meta_data :: binary - size(length), chunks :: binary>> = body_and_chunks
    {
      {:meta, meta_type, meta_data},
      chunks
    }
  end

  def handle_midi_event(<<type, tail :: binary>>) do
    event = midi_event(type)
    <<note_num, velocity, chunks :: binary>> = tail
    {
      {:midi, event, note_num, velocity},
      chunks
    }
  end

  defp midi_event(x) when x in 0x80..0x8f do :note_off end
  defp midi_event(x) when x in 0x90..0x9f do :note_on end
  defp midi_event(x) when x in 0xb0..0xbf do :ctrl_change end
  defp midi_event(x) do :unknown end  # todo: I don't know exactly
end
