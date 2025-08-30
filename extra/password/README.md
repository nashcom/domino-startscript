# Domino Password Extension Manager Helper for Linux

Domino on Windows provides support for storing the password of the server.id safely encrypted using the same technology used by the Notes client for Notes Shared Login (NSL).
The underlying functionality is the Microsoft Data Protection API. 

There isn't a comparable functionality on Linux. Therefore implementing a solution on Linux might need some external technology.
This project provides the base on the Domino side to call out to an external credential helper application, which could run with another user, query external information or similar.

The directory includes a simple sample credential example implementation.
Admins can plug-in any kind of credential helper providing the security level they require.


## Enable Password Extension Manager

Copy the binary into the Domino binary directory and make it executable

```
cp libnshsrvpw.so /opt/hcl/domino/notes/latest/linux
chmod 755 /opt/hcl/domino/notes/latest/linux/libnshsrvpw.so
```

Enable the password extension manager by setting or extending the following notes.ini variable

```
EXTMGR_ADDINS=libnshsrvpw.so
```
Provide and configure your password credential helper binary by setting the notes.ini variable **NshSrvPwCredentialProcess**.

## Special Notes.ini Setting for Password Extension Managers

Passwords must be applied very early in the startup process for a server.
When the recovery process of a server runs after a crash, transaction logging requires the password to apply recovery information to encrypted databases.

Loading Extension Managers that early comes with a limitation.
This happens before the NSF sub-system is fully initialized and the Extension Manager cannot invoke any C-API calls.
This includes all kind of Domino Logging! Therefore the code only uses normal printf operations for logging.
Those messages are not logged in log.nsf nor console.log.

This is required to guarantee the password is always applied -- also in Server startup recovery operations.


```
EXTMGR_ADDINS_EARLY=libnshsrvpw.so
```

## Environment Variables

- **NshSrvPwCredentialProcess**
  Full path to a helper binary which is invoked to retrieve the password from STDIN

- **NshSrvPwSetup**
  Set this variable to **1** to set the password of the server.id to the password retieved from the helper application.

- **NshSrvPwDebug**
  Debug option for tracing

- **EXTMGR_ADDINS=**
  Loads the extension manager

- **EXTMGR_ADDINS_EARLY**
  Required for password extension managers to be loaded early


## How to compile

The Extension Manager requires the Domino C-API to compile and link.
The provided makefile builds the extension manager and the sample helper application.

Tip: The Domino Container project provides an out of the box C-API environment which can be added at build time.


