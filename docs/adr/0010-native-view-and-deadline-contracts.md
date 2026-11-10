# 0010 — Native view identity and elapsed deadlines

**Status:** Accepted for candidate local.8; Android acceptance pending.

## Context

Local.7 tests covered isolated read models but missed native consumers and
shared callbacks. CPU time did not bound HTTP waits. Missing stats could block
startup indefinitely. Restoring the main loop after a UID timeout must preserve
the native readiness gate across both supported loaders.

## Decision

- Keep vendor immutable and apply checked transformations in the builder.
- Use libc CLOCK_MONOTONIC through existing LuaJIT FFI. Use an anonymous
  two-long buffer and void pointer compatible with pre-existing FFI declarations.
  Clock failure is explicit; no CPU-time fallback or added dependency.
- Bound UID discovery per invocation to 30 elapsed seconds/five requests.
  Only the genuine stats parser clears the pending UID flag. Readiness rejects
  pending UID on both NeoMLoader and MonetLoader. Manual `/stats` can recover.
- Native price responses retain the native consumer protocol, including exact
  validated quantity and value totals. Values represent asking-price snapshots,
  never claimed executed turnover. Reject unsafe aggregate overflow.
- Select prices by ID, variant, currency and server. Legacy name lookup is
  supported only when unambiguous; a remembered identity cannot silently switch
  to a different item after refresh. Offer explicit recovery selection.
- Use view generations to discard superseded callbacks. Compute identity choices
  through the host worker and cache by revision, server, currency, name and TTL.
  Render the controls inside existing children without enlarging native windows.

## Consequences

No new runtime dependency or licensing key is introduced. Tests must execute
actual native formatters/consumers alongside adapters, including reverse response
order, shared FFI state and missing UID. Desktop and mocked evidence do not
establish Android rendering, libc ABI or live server ACK acceptance.
