# CLI integration

Kaji exposes automation through its command-line interface. It does not run an MCP server.

The repository-provided CLI keeps the external integration boundary explicit and inspectable: a caller supplies arguments and observes output and exit status. When a running app must perform the action, the CLI talks to Kaji through a plain HTTP control API bound only to `127.0.0.1`. That loopback endpoint exists for the CLI; it does not implement MCP protocols, tool schemas, capability discovery, or a general integration server.

This decision applies to external automation of Kaji. Internal features may still invoke purpose-specific local tools when their own product contract requires it, but that does not turn Kaji into a general tool server.

Integrations should teach an agent or local workflow to call the Kaji CLI directly. For example, a user can ask an agent to read the CLI help and create a skill named `kaji` around the supported commands. Command behavior and help output are the source of truth for the available interface.
