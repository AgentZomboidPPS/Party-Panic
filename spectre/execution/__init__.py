"""Execution: the last gate between an approved order and a broker.

An order reaches a broker only if all of these hold:
1. compliance approved it (the OMS did that when the order was created)
2. trading is not halted (the kill switch)
3. it fits the trading limits (order size, daily total, order count, position size, symbol list)
4. for a live broker: live mode is switched on AND a named person approved this specific order

Paper trading uses the same path with a broker that fills at the latest known price, so
whatever works on paper has already been through every check a live order would face.
"""
