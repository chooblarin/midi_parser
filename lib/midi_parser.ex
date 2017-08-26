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

  def parse_track_chunk(body) do parse_track_chunk(body, []) end
  defp parse_track_chunk(<<>>, acc) do Enum.reverse acc end  
  defp parse_track_chunk(body, acc) do

    {delta_time, rest} = parse_variable_length_data(body)
    {value, rest_chunk} = parse_event(rest)
    result = {delta_time, value}

    parse_track_chunk(rest_chunk, [result | acc])
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

  def parse_event(data) do
    <<type, tail :: binary>> = data
    case type do

      # SysEx event
      0xF0 -> handle_sysex_event(data)
      0xF7 -> handle_sysex_event(data)

      # meta event
      0xFF -> handle_meta_event(data)

      # MIDI event
      _ -> handle_midi_event(data)
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
  defp midi_event(x) do
    IO.inspect x
    :unknown
  end  # todo: I don't know exactly
end
