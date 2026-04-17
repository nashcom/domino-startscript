# ClamAV Configuration for Domino CScan and nshdomav

This setup provides a ClamAV daemon (`clamd`) that can be used by:

* **HCL Domino CScan** (TCP only)
* **Nash!Com REST scanner (`nshdomav`)** (TCP *or* Unix socket)

---

# Overview

The ClamAV daemon is configured to expose:

* a **Unix socket** for fast local access
* a **TCP port (3310)** for Domino compatibility

---

# ClamAV Configuration (`clamd.conf`)

```text
LocalSocket /clamav/clamd.sock
LocalSocketMode 666
FixStaleSocket yes

TCPSocket 3310
TCPAddr 127.0.0.1

MaxThreads 10
MaxQueue 200
MaxScanSize 1G
MaxFileSize 512M
StreamMaxLength 512M
ConcurrentDatabaseReload yes
```

---

# Configuration Details

## LocalSocket

```
LocalSocket /clamav/clamd.sock
```

* Defines a Unix domain socket
* Used for local inter-process communication

```
LocalSocketMode 666
```

* Allows all local processes to access the socket
* Simplifies integration (can be tightened if required)

```
FixStaleSocket yes
```

* Automatically removes stale socket files after crashes

---

## TCP Interface

```
TCPSocket 3310
TCPAddr 127.0.0.1
```

* Enables ClamAV protocol over TCP
* Required for HCL Domino CScan
* Bound to localhost for security

---

## Performance and Limits

```
MaxThreads 10
```

* Maximum parallel scan threads

```
MaxQueue 200
```

* Maximum number of queued scan requests

```
MaxScanSize 1G
MaxFileSize 512M
StreamMaxLength 512M
```

* Limits scan sizes to prevent resource exhaustion
* Important for large attachments

```
ConcurrentDatabaseReload yes
```

* Allows virus database reload without interrupting scans

---

# Docker Compose Configuration

```yaml
services:

  clamav:
    container_name: clamav
    restart: always
    network_mode: host

    volumes:
      - ./clamd.conf:/etc/clamav/clamd.conf
      - clamav_db:/var/lib/clamav
      - ./data:/clamav

    environment:
      CLAMAV_NO_FRESHCLAMD: "false"
      CLAMAV_NO_CLAMD:      "false"

    healthcheck:
      test: ["CMD", "clamdcheck.sh"]
      interval: 60s
      retries: 3
      start_period: 120s

volumes:
  clamav_db:
```

---

# Docker Configuration Notes

## Host Networking

```
network_mode: host
```

* Container shares host network stack
* No Docker NAT or port mapping
* Firewall rules (UFW/nftables) apply normally

---

## Volumes

```
./clamd.conf:/etc/clamav/clamd.conf
```

* Custom ClamAV configuration

```
clamav_db:/var/lib/clamav
```

* Persistent virus signature database

```
./data:/clamav
```

* Exposes Unix socket to host
* Socket path on host: `./data/clamd.sock`

---

# Integration Options

## HCL Domino CScan

* Uses TCP connection only
* Configure:

```
localhost:3310
```

---

## nshdomav (Nash!Com database Scanner)

Supports both modes:

### Option 1: Unix socket (recommended)

```
/clamav/clamd.sock
```

Advantages:

* faster than TCP
* no network overhead
* no firewall exposure

---

### Option 2: TCP

```
localhost:3310
```

Useful when:

* socket access is not available
* remote access is required

---

# Testing

## TCP

```
echo PING | nc localhost 3310
```

Expected response:

```
PONG
```

---

## Unix Socket

```
echo PING | socat - UNIX-CONNECT:./data/clamd.sock
```

---

# Security Considerations

* TCP interface has **no authentication**
* Always bind to localhost unless properly firewalled and secured on network level
* Domino CScan supports TLS which can be added to this stack via NGINX

```
TCPAddr 127.0.0.1
```

* Unix socket is world-accessible (`666`)

  * acceptable for controlled environments
  * can be restricted if needed

---

# Summary

* Unix socket → best performance, used by `nshdomav`
* TCP port 3310 → required for HCL Domino
* Host networking ensures predictable firewall behavior
* Configuration supports both integration paths simultaneously

