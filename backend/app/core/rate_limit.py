from slowapi import Limiter
from slowapi.util import get_remote_address

# IP-keyed rate limiter — a stopgap against unauthenticated abuse of routes
# that don't require a login (comms, photo upload). Real per-user auth is the
# permanent fix for those routes; this just caps the damage until it lands.
limiter = Limiter(key_func=get_remote_address)
