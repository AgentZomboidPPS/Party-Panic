-- Per-player sliding window rate limiter for client -> server remotes (design doc §14).

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		_limit: number,
		_window: number,
		_calls: { [Player]: { number } },
	},
	RateLimiter
))

local limiters: { RateLimiter } = {}

function RateLimiter.new(limit: number, window: number): RateLimiter
	local self = setmetatable({
		_limit = limit,
		_window = window,
		_calls = {},
	}, RateLimiter)
	table.insert(limiters, self)
	return self
end

function RateLimiter.Check(self: RateLimiter, player: Player): boolean
	local now = os.clock()
	local calls = self._calls[player]
	if not calls then
		calls = {}
		self._calls[player] = calls
	end
	while calls[1] and now - calls[1] > self._window do
		table.remove(calls, 1)
	end
	if #calls >= self._limit then
		return false
	end
	table.insert(calls, now)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in limiters do
		limiter._calls[player] = nil
	end
end)

return RateLimiter
