#!/usr/bin/env python3
"""UDP impairment proxy for ENet: one listen port per simulated client link.

Usage: netsim.py <upstream_ip> <upstream_port> <listen_port>:<profile> [...]
Profiles (one-way, applied to both directions):
  lan     ~0.3 ms, no jitter
  wifi    2 ms base, 0-6 ms jitter, 0.3 % loss, 1 % chance of a 20-60 ms hold
  wifips  WiFi with power saving: 3 ms base, 0-10 ms jitter, 1 % loss,
          every ~1 s a 50-170 ms hold (packets queue and release in a burst)
  bad     15 ms base, 0-30 ms jitter, 3 % loss, 3 % chance of a 80-250 ms hold, 1 % reorder
Packets of one flow stay in order (except "bad"'s reorder), so jitter shows up as bursts,
as on real WiFi. Prints per-link stats every 10 s.
"""
import heapq
import random
import select
import socket
import sys
import time

PROFILES = {
	"lan": dict(base=0.3, jitter=0.2, loss=0.0, hold_p=0.0, hold=(0, 0), hold_period=0, reorder=0.0),
	"wifi": dict(base=2, jitter=6, loss=0.003, hold_p=0.01, hold=(20, 60), hold_period=0, reorder=0.0),
	"wifips": dict(base=3, jitter=10, loss=0.01, hold_p=0.0, hold=(50, 170), hold_period=1.0, reorder=0.0),
	"bad": dict(base=15, jitter=30, loss=0.03, hold_p=0.03, hold=(80, 250), hold_period=0, reorder=0.01),
}


class Direction:
	def __init__(self, prof):
		self.p = prof
		self.last_out = 0.0
		self.hold_until = 0.0
		self.next_periodic = time.monotonic() + random.random()
		self.sent = 0
		self.dropped = 0
		self.delay_sum = 0.0
		self.delay_max = 0.0

	def schedule(self, now):
		"""Send time for a packet arriving now, or None to drop it."""
		p = self.p
		if random.random() < p["loss"]:
			self.dropped += 1
			return None
		if p["hold_period"] and now >= self.next_periodic:
			self.hold_until = now + random.uniform(*p["hold"]) / 1000.0
			self.next_periodic = now + p["hold_period"] * random.uniform(0.6, 1.4)
		elif p["hold_p"] and now >= self.hold_until and random.random() < p["hold_p"]:
			self.hold_until = now + random.uniform(*p["hold"]) / 1000.0
		t = now + (p["base"] + random.random() * p["jitter"]) / 1000.0
		t = max(t, self.hold_until)
		if random.random() >= p["reorder"]:
			t = max(t, self.last_out)
			self.last_out = t
		d = t - now
		self.sent += 1
		self.delay_sum += d
		self.delay_max = max(self.delay_max, d)
		return t

	def stats(self):
		n = max(self.sent, 1)
		s = "sent=%d drop=%d avg=%.1fms max=%.0fms" % (self.sent, self.dropped, self.delay_sum / n * 1000, self.delay_max * 1000)
		self.sent = self.dropped = 0
		self.delay_sum = self.delay_max = 0.0
		return s


def main():
	up = (sys.argv[1], int(sys.argv[2]))
	links = {}  # listen socket -> dict
	sock_info = {}  # any socket -> (kind, link, client_addr)
	for spec in sys.argv[3:]:
		port, prof = spec.split(":")
		ls = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
		ls.bind(("0.0.0.0", int(port)))
		ls.setblocking(False)
		link = dict(port=int(port), prof=prof, listen=ls, clients={})
		links[ls] = link
		sock_info[ls] = ("listen", link, None)
		print("listening on", port, "profile", prof, "->", up, flush=True)
	heap = []
	seq = 0
	last_stats = time.monotonic()
	while True:
		now = time.monotonic()
		timeout = 0.05
		if heap:
			timeout = max(0.0, min(timeout, heap[0][0] - now))
		r, _, _ = select.select(list(sock_info.keys()), [], [], timeout)
		now = time.monotonic()
		for s in r:
			kind, link, caddr = sock_info[s]
			while True:
				try:
					data, addr = s.recvfrom(65536)
				except BlockingIOError:
					break
				if kind == "listen":
					c = link["clients"].get(addr)
					if c is None:
						us = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
						us.bind(("0.0.0.0", 0))
						us.setblocking(False)
						prof = PROFILES[link["prof"]]
						c = dict(up=us, to_host=Direction(prof), to_client=Direction(prof))
						link["clients"][addr] = c
						sock_info[us] = ("up", link, addr)
						print("port", link["port"], "new client", addr, flush=True)
					at = c["to_host"].schedule(now)
					if at is not None:
						seq += 1
						heapq.heappush(heap, (at, seq, c["up"], data, up))
				else:
					c = link["clients"][caddr]
					at = c["to_client"].schedule(now)
					if at is not None:
						seq += 1
						heapq.heappush(heap, (at, seq, link["listen"], data, caddr))
		while heap and heap[0][0] <= now:
			_, _, s, data, dest = heapq.heappop(heap)
			try:
				s.sendto(data, dest)
			except OSError:
				pass
		if now - last_stats >= 10:
			last_stats = now
			for link in links.values():
				for addr, c in link["clients"].items():
					print("stats port=%d %s up[%s] down[%s]" % (link["port"], link["prof"], c["to_host"].stats(), c["to_client"].stats()), flush=True)


if __name__ == "__main__":
	main()
