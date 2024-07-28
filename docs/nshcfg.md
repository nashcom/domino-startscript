---
layout: default
title: Domino Config Menu
nav_order: 6
description: "One-Touch Domino config menu"
has_children: false
---

# One-touch Domino Setup Support

Domino One Touch Setup is the new and flexible setup introduced in Domino 12.  
The JSON based setup allows many configuration options.

The Domino Start Script and the Domino Container Script both leverage the **nshcfg.sh** providing a configurable menu and variable replacement option for OTS setups.

The menu itself is configured via a JSON file. By default the `/etc/sysconfig/domino.cfg` is used.  


## Invoking the OTS Menu

The menu can have different type of prefixes and extensions.

### file:/ Prefix

A local file on the same host.

### https:// Prefix

A remote location requested via Curl.

### .json Extension

A OTS JSON file

### .cfg Extension

A menu file containing menu entries

### Domain

If only a domain is specified, the URL is completed appending `/.well-known/domino.cfg`

Example:

```
domino setup https://domino.lab
```

is translated into the well-known configuration URL

```
https://nashcom.lab/.well-known/domino.cfg
```


### "auto" Configuration

The term `auto` checks the domain of the host and completes it with the well-known configuration URL.

```
domino setup auto
```

## Configuration

A menu can be invoked with different entry points, which can be selected.  
If no configuration is specified the `index` entry is used.

The menu allows relative and absolute addressing.  
If no prefix is specified, an entry in the current file is selected.  
This allows menu entries spanning multiple files and remote locations to build cascaded menus.

The default configuration used by the Domino Start Script and Container Control script 

## Default configuration - /etc/sysconfig/domino.cfg

```
{
  "index": {
    "cfg": [
      {
        "name": ".",
        "index": "/onetouch",
        "URL": ""
      }
    ]
  },

  "onetouch": {
    "cfg": [
      {
        "name": "First server JSON",
        "oneTouchJSON": "/opt/nashcom/startscript/OneTouchSetup/first_server.json",
        "oneTouchENV": "/opt/nashcom/startscript/OneTouchSetup/first_server.env"
      },
      {
        "name": "Additional server JSON",
        "oneTouchJSON": "/opt/nashcom/startscript/OneTouchSetup/additional_server.json",
        "oneTouchENV": "/opt/nashcom/startscript/OneTouchSetup/additional_server.env"
      }
    ]
  }
}
```

## Configuration entries

A configuration entry defines an entry. The following options are available:

- **name**  
  Defines the name of the entry
  
- **oneTouchJSON**  
  Defines a OTS JSON file
  
- **oneTouchENV**  
  Defines a OTS environment file
  
- **URL**  
  An URL entry pointing to another configuration file
