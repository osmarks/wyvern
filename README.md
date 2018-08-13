# Wyvern
A centralized storage management system for Minecraft. Basically Dragon, rewritten for sanity and improved networking/error handling.
Requires Plethora Peripherals by SquidDev (as that's what allows item transfer by wired network).

## Setup
`installer.lua` is recommended for running everything.
Get it with `https://osmarks.tk/git/osmarks/wyvern/raw/branch/master/installer.lua`.

Run `installer install` to download everything. It will open an editor for the config file, allowing setup of a node.
When prompted for a program to run on startup, say `client` to configure it as a client or `backend-chests` to run the chest backend.

If you just want to update Wyvern, run `installer update`.

### Networking & Hardware

```
Chests ───────┐
   │          │
Server ─── Buffer
   │          │
   └────┬─────┘
        │
        ├────────── Processing (not implemented yet)
        │
        │
   ┌────┴──┬───────┐
Client  Client  Client
```
* **Chests** is a set of chests and/or shulker boxes, connected via networking cables and modems, to the **Server** and **Buffer**. Cookie jars are not compatible.
* **Buffer** is a dropper with a wired connection on the chests' side and clients' side.
* **Server** is a computer running `backend-chests`. Other backends may eventually become available. It must be connected to the chests, clients, and both sides of the buffers.
* **Client** is a crafty turtle running `client`. It must be connected to the server and external side of the buffers.
* **Processing** will be used for autocrafting systems. It is not yet implemented.

### Configuration
Configuration is stored in `wyvern_config.tbl` in lua table syntax as used by `textutils.(un)serialise`.

#### Client
`network_name` must contain the network name (thing displayed when modem beside it is rightclicked) of the client turtle.

#### Server
`buffer_internal` must contain the network name of the buffer on the chest side.
`buffer_external` must contain the network name of the buffer on the client side.
`modem_internal` can contain the network name of the server on the chest side. This is only required if your network contains chests on the client side which are connected.

## Warnings
* Inserting/extracting items manually into/out of chests will result in the index being desynchronised with the actual items. To correct the index, run `reindex` in the CLI client.
* If you try and extract items when the storage server is still starting up, it may fail, as not all chests will have been indexed yet.
* There are currently small problems with extracting certain quantities of items from storage. Yes, it should probably be by stack.
* Yes, I am kind of using git wrong, but editing networked CC programs sanely is *very hard*. Tell me if you find a better solution.