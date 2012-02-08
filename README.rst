Note: this package depend on git HEAD version of `conduit library <http://hackage.haskell.org/package/conduit>`_ .

The problem this program solves described here (in chinese):
`http://blog.codingnow.com/2011/05/xtunnel.html <http://blog.codingnow.com/2011/05/xtunnel.html>`_ , and here is a solution written in golang: `http://blog.codingnow.com/cloud/XTunnel <http://blog.codingnow.com/cloud/XTunnel>`_ .

The basic idea is this: ::

  client => local agent ->-GFW->- remote agent => target server

The local agent pass all the tcp requests received to a remote agent, the remote agent pass them to our target server. Mantain only one persistent connection between local agent and remote agent. All the messages passed through the `GFW <http://en.wikipedia.org/wiki/GFW>`_ need to be encrypted for well known reason.

This solution demonstrates that haskell lightweight threads is very convinient for highly concurrent system, it also demonstrates multiple thread communication mechanism: IORef with atomicModifyIORef, MVar, STM.

It takes advantage of multiple high quality haskell libraries:

* `bytestring <hackage.haskell.org/package/bytestring>`_ and `blaze-builder <http://hackage.haskell.org/package/blaze-builder>`_ provides fast buffer management and construction.

* `attoparsec <http://hackage.haskell.org/package/attoparsec>`_  to parse streamlined network protocol, although the message format in this case is too simple to show the real strength of it.

* `cereal <http://hackage.haskell.org/package/cereal>`_ to parse binary data, manually handle correct byte-order is a pain.

* `conduit <http://hackage.haskell.org/package/conduit>`_ is a stream processing framework, this concept maybe rare in language other than haskell, if you find it strange, you can find great intruction documentation here: `Conduits in Five Minutes <http://www.yesodweb.com/book/conduit>`_ .

* `network-conduit <http://hackage.haskell.org/package/network-conduit>`_ provides a clean and complete tcp server/client interface to work with.