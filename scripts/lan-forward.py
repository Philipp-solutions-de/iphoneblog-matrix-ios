#!/usr/bin/env python3
"""Forward ports from the Mac's LAN address to its loopback, for perf tests on a real device.

    /usr/bin/python3 scripts/lan-forward.py <lan-address> <port> [<port> ...]

The test homeserver and the blog fixture listen on 127.0.0.1 only. A device reaches the Mac
over the LAN, so this listens on <lan-address>:<port> and forwards each connection to
127.0.0.1:<port>. Run with /usr/bin/python3: the macOS firewall lets Apple's signed Python
accept connections, and the servers stay on loopback. Standard library only, Python 3.9.
docs/performance.md, "On a device".
"""
import asyncio
import sys


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        writer.close()


def handler(port):
    async def handle(client_reader, client_writer):
        try:
            server_reader, server_writer = await asyncio.open_connection("127.0.0.1", port)
        except OSError:
            client_writer.close()
            return
        await asyncio.gather(pipe(client_reader, server_writer), pipe(server_reader, client_writer))
    return handle


async def main(address, ports):
    servers = [await asyncio.start_server(handler(p), address, p) for p in ports]
    print(f"lan-forward: {address} ports {', '.join(map(str, ports))} -> 127.0.0.1", flush=True)
    await asyncio.gather(*(s.serve_forever() for s in servers))


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], [int(p) for p in sys.argv[2:]]))
