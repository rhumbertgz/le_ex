defmodule BLE.Metadata do
  defstruct nodeId: -1, role: :worker, status: :offline, leader: nil, timerRef: nil
end
