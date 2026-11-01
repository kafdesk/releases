# KafDesk — native Kafka desktop client (GUI) for macOS, Windows and Linux

KafDesk is a fast native desktop client for Apache Kafka with a built-in MCP server for AI agents.
Browse topics and messages, watch consumer-group lag, reset offsets, work with Schema Registry and
Kafka Connect. No JVM, no cloud account.

**Download:** https://kafdesk.com/download (every file and its SHA-256 are listed there and in
`SHA256SUMS` of each release). Every feature is free for 14 days, no account and no card.

![KafDesk showing Avro messages decoded through Schema Registry](https://kafdesk.com/shots/messages.png)

## Why KafDesk

- **Native and small:** a 39 MB download for macOS (signed and notarized, updates itself),
  Windows x64 and Arm installers, deb and rpm for Linux x86_64 and arm64. No Java to install.
- **Fast:** 50,000 JSON messages fetched and decoded in 0.8 s; a text search through 1,000,000
  messages in 5.5 s (median of 5 runs, 2018 Intel MacBook Pro, Kafka 3.9 on the same machine).
- **Kafka MCP server:** `kafdesk-mcp` lets Claude Code, Cursor, Codex or any MCP client list
  topics, sample messages and inspect consumer lag through the connections saved in KafDesk.
  Read-only by default; every call is logged.
- **Safe on production:** protected clusters get a red frame and typed-name confirmations;
  a connection can be read-only.

## Features

- Connections: PLAINTEXT, TLS with client certificates, SASL PLAIN, SCRAM-SHA-256/512,
  OAUTHBEARER, AWS IAM for Amazon MSK; passwords in the OS keychain.
- Messages: live tail, seek by time or offset, search with filter expressions, JSON, Avro,
  Protobuf and JSON Schema decoding, export to NDJSON, produce with headers.
- Consumer groups: lag per partition with a trend, offset resets with a dry run.
- Schema Registry, Kafka Connect, topic and broker configs, ACLs, quotas, cluster compare.
- Teams: shared connection profiles from a file or URL, seats and managed key deployment.

## Pricing

Personal $79 once (3 devices, a year of updates, keeps working after). Team $99 per seat a year.
Free for open-source maintainers and students. Details: https://kafdesk.com/#pricing

## Alternatives compared

- [Conduktor Desktop alternative](https://kafdesk.com/vs/conduktor-desktop) — Conduktor Desktop is end-of-life.
- [Offset Explorer (Kafka Tool) alternative](https://kafdesk.com/vs/offset-explorer)

## Support

support@kafdesk.com · Changelog: https://kafdesk.com/changelog

Apache Kafka is a trademark of the Apache Software Foundation. KafDesk is not affiliated with it.
