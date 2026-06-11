defmodule RompCrm.Scheduling.CalendarSource do
  @moduledoc """
  Behaviour for busy-block providers feeding `RompCrm.Scheduling.AvailabilityEngine`.

  Implementations are read-only: they report `%{start: DateTime, end: DateTime}`
  UTC intervals during which the technician is unavailable. Event titles or any
  other personal calendar details must never leave the implementation.

  `credential` is implementation-defined (internal source takes a context map;
  external sources take a decrypted credential map).
  """

  alias RompCrm.Scheduling.AvailabilityEngine

  @callback fetch_busy_blocks(
              credential :: term(),
              date_range :: {Date.t(), Date.t()},
              timezone :: String.t()
            ) :: {:ok, [AvailabilityEngine.block()]} | {:error, term()}
end
