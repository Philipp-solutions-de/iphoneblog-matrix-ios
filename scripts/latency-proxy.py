"""A TCP forwarder with a phone's network delay, for the performance tests (scripts/perf.sh).

    scripts/latency-proxy.py <listen port> <target port> <one-way ms>

Holds every chunk the given time in each direction, so a request and its answer cost about
twice that: 50 gives the 100 ms round trip of a phone on LTE. Against the local Synapse
every request answers at once, and start-up steps that wait one after another do not show
(testOneChatAfterLaunch, docs/performance.md)."""
import asyncio, sys
listen, target, delay = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]) / 1000

async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            await asyncio.sleep(delay)
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        writer.close()

async def handle(client_reader, client_writer):
    server_reader, server_writer = await asyncio.open_connection("127.0.0.1", target)
    await asyncio.gather(pipe(client_reader, server_writer), pipe(server_reader, client_writer))

async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", listen)
    async with server:
        await server.serve_forever()

asyncio.run(main())
