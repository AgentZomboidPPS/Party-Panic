-- Minimal signal for in-script events (no BindableEvent round trips, keeps table identity).

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

local Signal = {}
Signal.__index = Signal

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	_handlers: { [any]: (T...) -> () },
}

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal:Connect(callback)
	local handlers = self._handlers
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		conn.Connected = false
		handlers[conn] = nil
	end
	handlers[connection] = callback
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
